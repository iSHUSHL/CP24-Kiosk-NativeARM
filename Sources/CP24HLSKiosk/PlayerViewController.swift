import AppKit
import AVFoundation
import AVKit

@MainActor
final class PlayerViewController: NSViewController {
    var initialChannel: Channel = .cp24
    private(set) var lastPlaybackEvent = "Not started"
    private var recentPlaybackEvents: [String] = []
    var fallbackRequested: ((Channel) -> Void)?
    var healthStatusChanged: ((Bool, String) -> Void)?

    private let nativePlayerView = NSView()
    private let playerLayer = AVPlayerLayer()
    private let statusLabel = NSTextField(labelWithString: "")
    private let nowPlayingLabel = NSTextField(labelWithString: "")

    private var player = AVPlayer()
    private let fairPlay = FairPlayResourceLoader()
    private var currentChannel: Channel = .cp24
    private var qualityTimer: Timer?
    private var channelQuality: [Channel: AdaptiveQuality] = [:]
    private var qualityLastTime: Double?
    private var bufferingSince: Date?
    private var stablePlaybackSince: Date?
    private var transferBytes: Int64 = 0
    private var transferDuration: TimeInterval = 0
    private var lastThroughput: Double?
    private var throughputAt = Date.distantPast
    private var monitorTimer: Timer?
    private var statusTimer: Timer?
    private var nowPlayingTimer: Timer?
    private var lastPlayerTime: Double?
    private var lastProgressAt = Date()
    private var lastRecoveryAt = Date.distantPast
    private var recoveryDelay: TimeInterval = 6
    private var loadedAt = Date()
    private var recoveryWindowStartedAt = Date.distantPast
    private var recoveryAttemptsInWindow = 0
    private var consecutiveMissingVideoChecks = 0
    private var itemStatusObservation: NSKeyValueObservation?
    private var timeControlObservation: NSKeyValueObservation?
    private var isStoppedByUser = false
    private var isWaitingForNetwork = false

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.cgColor

        nativePlayerView.translatesAutoresizingMaskIntoConstraints = false
        nativePlayerView.wantsLayer = true
        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resize
        playerLayer.player = player
        nativePlayerView.layer = playerLayer
        container.addSubview(nativePlayerView)

        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        statusLabel.isBezeled = false
        statusLabel.isEditable = false
        statusLabel.drawsBackground = true
        statusLabel.backgroundColor = NSColor.black.withAlphaComponent(0.68)
        statusLabel.textColor = .white
        statusLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        statusLabel.alignment = .center
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.isHidden = true
        statusLabel.layer?.cornerRadius = 6
        statusLabel.layer?.masksToBounds = true
        container.addSubview(statusLabel)

        nowPlayingLabel.translatesAutoresizingMaskIntoConstraints = false
        nowPlayingLabel.isBezeled = false
        nowPlayingLabel.isEditable = false
        nowPlayingLabel.drawsBackground = true
        nowPlayingLabel.backgroundColor = NSColor.black.withAlphaComponent(0.58)
        nowPlayingLabel.textColor = .white
        nowPlayingLabel.font = .systemFont(ofSize: 12, weight: .semibold)
        nowPlayingLabel.alignment = .center
        nowPlayingLabel.lineBreakMode = .byTruncatingTail
        nowPlayingLabel.isHidden = true
        nowPlayingLabel.layer?.cornerRadius = 5
        nowPlayingLabel.layer?.masksToBounds = true
        container.addSubview(nowPlayingLabel)

        NSLayoutConstraint.activate([
            nativePlayerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            nativePlayerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            nativePlayerView.topAnchor.constraint(equalTo: container.topAnchor),
            nativePlayerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            statusLabel.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 18),
            statusLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            statusLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.72),
            statusLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 34),

            nowPlayingLabel.trailingAnchor.constraint(equalTo: container.safeAreaLayoutGuide.trailingAnchor, constant: -18),
            nowPlayingLabel.bottomAnchor.constraint(equalTo: container.safeAreaLayoutGuide.bottomAnchor, constant: -18),
            nowPlayingLabel.widthAnchor.constraint(lessThanOrEqualTo: container.widthAnchor, multiplier: 0.42),
            nowPlayingLabel.heightAnchor.constraint(greaterThanOrEqualToConstant: 26)
        ])

        view = container
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        playerLayer.frame = nativePlayerView.bounds
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        player.allowsExternalPlayback = false
        player.automaticallyWaitsToMinimizeStalling = true
        StreamHealthLog.append("Player ready")
        load(initialChannel, reason: "Starting \(initialChannel.title)")
        startMonitoring()
    }

    func load(_ channel: Channel, reason: String? = nil) {
        isStoppedByUser = false
        currentChannel = channel
        recordPlaybackEvent(reason ?? "Channel selected")
        resetHealth()
        StreamHealthLog.append("Loading \(channel.title): \(reason ?? "channel switch")")
        showStatus(reason ?? "Switching to \(channel.title)")
        showNowPlaying(channel)
        startMonitoring()

        switch channel.playback {
        case .native(let url):
            loadNativeStream(url)
        }
    }

    func recoverNow(reason: String) {
        guard !isStoppedByUser, !isWaitingForNetwork else { return }
        let now = Date()
        guard now.timeIntervalSince(lastRecoveryAt) >= recoveryDelay else { return }
        recordRecoveryAttempt(at: now)
        markUnhealthy(reason)
        recordPlaybackEvent("Reload requested: " + reason)
        StreamHealthLog.append("Recovery attempt \(recoveryAttemptsInWindow) for \(currentChannel.title): \(reason)")

        lastRecoveryAt = now
        recoveryDelay = min(recoveryDelay * 1.6, 60)
        if recoveryAttemptsInWindow >= 3 {
            StreamHealthLog.append("\(currentChannel.title) recovery limit reached; requesting enabled fallback")
            showStatus("\(currentChannel.title) unavailable, switching")
            let failedItem = player.currentItem
            fallbackRequested?(currentChannel.next)
            if player.currentItem !== failedItem { return }
            // No enabled fallback: keep retrying this channel with bounded backoff.

        }

        showStatus("Recovering \(currentChannel.title)")

        switch currentChannel.playback {
        case .native(let url):
            loadNativeStream(url)
        }

        lastProgressAt = Date()
        lastPlayerTime = nil
        consecutiveMissingVideoChecks = 0
    }

    func stopPlayback() {
        StreamHealthLog.append("Stopping playback for \(currentChannel.title)")
        recordPlaybackEvent("Playback stopped")
        isStoppedByUser = true
        monitorTimer?.invalidate()
        monitorTimer = nil
        qualityTimer?.invalidate()
        qualityTimer = nil
        statusTimer?.invalidate()
        statusTimer = nil
        nowPlayingTimer?.invalidate()
        nowPlayingTimer = nil
        statusLabel.isHidden = true
        nowPlayingLabel.isHidden = true

        clearNativeObservers()
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    func showNetworkWaiting(_ waiting: Bool) {
        isWaitingForNetwork = waiting
        channelQuality[currentChannel]?.interruptStability()
        stablePlaybackSince = nil
        statusTimer?.invalidate()
        statusTimer = nil
        if waiting {
            statusLabel.stringValue = "  Waiting for network  "
            statusLabel.isHidden = false
        } else {
            statusLabel.isHidden = true
            showStatus(currentChannel.title)
        }
    }

    private func loadNativeStream(_ url: URL) {
        StreamHealthLog.append("Starting native stream for \(currentChannel.title)")
        clearNativeObservers()
        playerLayer.player = nil
        player.replaceCurrentItem(with: nil)
        playerLayer.player = player

        let headers = [
            "User-Agent": "AppleCoreMedia/1.0.0.22G120 (Macintosh; U; Intel Mac OS X 15_5; en_us)"
        ]
        let asset = AVURLAsset(url: url, options: ["AVURLAssetHTTPHeaderFieldsKey": headers])
        if currentChannel == .cp24 {
            asset.resourceLoader.setDelegate(fairPlay, queue: fairPlay.queue)
        }
        loadedAt = Date()
        let item = AVPlayerItem(asset: asset)
        var quality = channelQuality[currentChannel] ?? AdaptiveQuality()
        quality.interruptStability()
        channelQuality[currentChannel] = quality
        qualityLastTime = nil
        bufferingSince = nil
        stablePlaybackSince = nil
        transferBytes = 0
        transferDuration = 0
        lastThroughput = nil
        throughputAt = .distantPast
        applyQuality(to: item, reason: "Stream start")
        item.canUseNetworkResourcesForLiveStreamingWhilePaused = true

        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nativeItemStalled(_:)),
            name: .AVPlayerItemPlaybackStalled,
            object: item
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(nativeItemFailed(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: item
        )

        player.replaceCurrentItem(with: item)
        observe(item)
        player.play()
    }

    private func observe(_ item: AVPlayerItem) {
        itemStatusObservation = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                guard let self, self.player.currentItem === item else { return }
                switch item.status {
                case .readyToPlay:
                    self.disableNativeCaptions(on: item)
                    self.player.play()
                    StreamHealthLog.append("Native stream ready for \(self.currentChannel.title)")
                    self.showNowPlaying(self.currentChannel)
                    self.showStatus(self.currentChannel.title)
                case .failed:
                    StreamHealthLog.append("Native stream failed for \(self.currentChannel.title): \(item.error?.localizedDescription ?? "unknown error")")
                    self.recoverNow(reason: "Stream failed")
                default:
                    break
                }
            }
        }

        timeControlObservation = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                guard let self, !self.isStoppedByUser, self.player.currentItem === item else { return }
                if player.timeControlStatus == .playing {
                    StreamHealthLog.append("Playback active for \(self.currentChannel.title)")
                }
            }
        }
    }

    private func clearNativeObservers() {
        itemStatusObservation?.invalidate()
        timeControlObservation?.invalidate()
        itemStatusObservation = nil
        timeControlObservation = nil
        NotificationCenter.default.removeObserver(self)
    }

    private func disableNativeCaptions(on item: AVPlayerItem) {
        Task {
            if let group = try? await item.asset.loadMediaSelectionGroup(for: .legible) {
                item.select(nil, in: group)
            }
        }
    }

    @objc private func nativeItemStalled(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, player.currentItem === item,
              !isStoppedByUser, !isWaitingForNetwork,
              !player.isOutputObscuredDueToInsufficientExternalProtection else { return }
        recordPlaybackEvent("Playback stalled; allowing buffer refill")
        stablePlaybackSince = nil
        if channelQuality[currentChannel, default: AdaptiveQuality()].reduce(at: Date()) {
            applyQuality(to: item, reason: "Playback stalled")
        }
        StreamHealthLog.append("Native stream stalled for \(currentChannel.title)")
        // Let AVPlayer refill its buffer; the health monitor retries sustained stalls.
        player.play()
    }

    @objc private func nativeItemFailed(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem, player.currentItem === item else { return }
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        recordPlaybackEvent("Playback failure: " + (error?.localizedDescription ?? item.error?.localizedDescription ?? "Unknown error"))
        StreamHealthLog.append("Native stream playback failure for \(currentChannel.title): \(error?.localizedDescription ?? item.error?.localizedDescription ?? "unknown error")")
        recoverNow(reason: "Stream failed")
    }

    private func startMonitoring() {
        monitorTimer?.invalidate()
        monitorTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkNativePlaybackHealth()
            }
        }
        monitorTimer?.tolerance = 3
        qualityTimer?.invalidate()
        qualityTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkAdaptiveQuality() }
        }
        qualityTimer?.tolerance = 1
    }

    private func checkNativePlaybackHealth() {
        guard !isStoppedByUser, !isWaitingForNetwork else { return }
        guard let item = player.currentItem else {
            StreamHealthLog.append("Health check: no stream loaded for \(currentChannel.title)")
            recoverNow(reason: "No stream loaded")
            return
        }

        if player.isOutputObscuredDueToInsufficientExternalProtection {
            // Output protection is not a bandwidth failure; don't reload or lower quality.
            showStatus("Protected video unavailable during screen capture")
            return
        }

        if item.status == .failed {
            StreamHealthLog.append("Health check: stream failed for \(currentChannel.title)")
            recoverNow(reason: "Stream failed")
            return
        }

        if player.rate == 0 && Date().timeIntervalSince(lastProgressAt) > 35 {
            StreamHealthLog.append("Health check: playback paused, nudging \(currentChannel.title)")
            player.play()
        }

        let seconds = player.currentTime().seconds
        if seconds.isFinite {
            if let previous = lastPlayerTime, seconds > previous + 0.25 {
                lastProgressAt = Date()
                if nativeVideoIsVisible(on: item) {
                    if stablePlaybackSince == nil { stablePlaybackSince = Date() }
                    if Date().timeIntervalSince(stablePlaybackSince!) >= 60 {
                        recoveryDelay = 6
                        resetRecoveryWindow()
                    }
                    markHealthy("Native playback progressing")
                }
            }

            if lastPlayerTime == nil {
                lastProgressAt = Date()
            }

            lastPlayerTime = seconds
        }

        if Date().timeIntervalSince(loadedAt) > 60 && !nativeVideoIsVisible(on: item) {
            consecutiveMissingVideoChecks += 1
            StreamHealthLog.append("Health check: \(currentChannel.title) video did not become visible after startup")
            markUnhealthy("Video not visible")
            if consecutiveMissingVideoChecks >= 2 {
                recoverNow(reason: "Video not visible")
                return
            }
        }

        if nativeVideoIsVisible(on: item) { consecutiveMissingVideoChecks = 0 }

        if item.isPlaybackBufferEmpty && Date().timeIntervalSince(lastProgressAt) > 45 {
            StreamHealthLog.append("Health check: buffer empty too long for \(currentChannel.title)")
            recoverNow(reason: "Buffering too long")
            return
        }

        if Date().timeIntervalSince(lastProgressAt) > 75 {
            StreamHealthLog.append("Health check: no playback progress for \(currentChannel.title)")
            recoverNow(reason: "Playback stopped")
        }
    }

    private func applyQuality(to item: AVPlayerItem, reason: String) {
        let quality = channelQuality[currentChannel] ?? AdaptiveQuality()
        recordPlaybackEvent("Quality cap \(quality.peakBitRate / 1_000_000) Mbps: \(reason)")
        item.preferredPeakBitRate = quality.peakBitRate
        item.preferredForwardBufferDuration = quality.forwardBuffer
        StreamHealthLog.append("Adaptive quality for \(currentChannel.title): \(quality.peakBitRate / 1_000_000) Mbps preferred cap, \(Int(quality.forwardBuffer))s buffer — \(reason)")
    }

    private func checkAdaptiveQuality() {
        guard !isStoppedByUser, !isWaitingForNetwork,
              let item = player.currentItem, item.status == .readyToPlay else { return }
        guard !player.isOutputObscuredDueToInsufficientExternalProtection else {
            channelQuality[currentChannel]?.interruptStability()
            stablePlaybackSince = nil
            return
        }
        let now = Date()
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        let progressing = qualityLastTime.map { seconds > $0 + 0.25 } ?? false
        qualityLastTime = seconds
        let ahead = item.loadedTimeRanges.map(\.timeRangeValue).filter {
            let start = $0.start.seconds
            return start <= seconds + 0.1 && CMTimeRangeGetEnd($0).seconds >= seconds
        }.map { CMTimeRangeGetEnd($0).seconds - seconds }.max() ?? 0

        // Use new transferred bytes/time only; repeatedly reading a stale log must
        // not look like fresh bandwidth evidence for a quality increase.
        if let events = item.accessLog()?.events {
            let bytes = events.reduce(Int64(0)) { $0 + max(0, $1.numberOfBytesTransferred) }
            let duration = events.reduce(0.0) { $0 + max(0, $1.transferDuration) }
            if bytes > transferBytes, duration > transferDuration {
                lastThroughput = Double(bytes - transferBytes) * 8 / (duration - transferDuration)
                throughputAt = now
            }
            transferBytes = bytes
            transferDuration = duration
        }
        let buffering = !progressing && (item.isPlaybackBufferEmpty || player.timeControlStatus == .waitingToPlayAtSpecifiedRate)
        if buffering {
            stablePlaybackSince = nil
            if bufferingSince == nil {
                bufferingSince = now
                recordPlaybackEvent("Buffering started")
            }
        } else {
            if bufferingSince != nil && progressing { recordPlaybackEvent("Playback resumed after buffering") }
            bufferingSince = nil
            if !progressing { stablePlaybackSince = nil }
        }
        let sustainedBuffering = bufferingSince.map { now.timeIntervalSince($0) >= 5 } ?? false
        let freshThroughput = now.timeIntervalSince(throughputAt) <= 15 ? lastThroughput : nil
        if channelQuality[currentChannel, default: AdaptiveQuality()].sample(
            at: now, progressing: progressing, buffering: sustainedBuffering,
            bufferSeconds: ahead, throughput: freshThroughput) {
            applyQuality(to: item, reason: sustainedBuffering ? "Buffering" : "Connection and buffer assessment")
        }
        if sustainedBuffering {
            markUnhealthy("Buffering")
            showStatus("Buffering \(currentChannel.title) — adapting quality")
        }
    }

    private func recordPlaybackEvent(_ message: String) {
        let stamp = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
        lastPlaybackEvent = "\(stamp) — \(currentChannel.title): \(message)"
        recentPlaybackEvents.append(lastPlaybackEvent)
        if recentPlaybackEvents.count > 8 { recentPlaybackEvents.removeFirst() }
    }

    var playbackDiagnostics: String {
        guard let item = player.currentItem else {
            return "Playback stopped.\n\nRecent events\n" + recentPlaybackEvents.joined(separator: "\n")
        }
        let time = player.currentTime().seconds
        let buffered = time.isFinite ? item.loadedTimeRanges.map(\.timeRangeValue).filter {
            $0.start.seconds <= time + 0.1 && CMTimeRangeGetEnd($0).seconds >= time
        }.map { CMTimeRangeGetEnd($0).seconds - time }.max() ?? 0 : 0
        let size = item.presentationSize
        let resolution = size.width.isFinite && size.height.isFinite && size.width > 0 && size.height > 0 ? "\(Int(size.width)) × \(Int(size.height))" : "Waiting for video"
        let indicated = item.accessLog()?.events.last?.indicatedBitrate ?? 0
        let bitrate = indicated.isFinite && indicated > 0 ? String(format: "%.2f Mbps", indicated / 1_000_000) : "Not reported"
        let throughput = Date().timeIntervalSince(throughputAt) <= 15 ? lastThroughput : nil
        let speed = throughput.flatMap { $0.isFinite && $0 > 0 ? String(format: "%.2f Mbps", $0 / 1_000_000) : nil } ?? "Waiting for fresh measurement"
        let state = player.isOutputObscuredDueToInsufficientExternalProtection ? "Protected output blocked" :
            (isWaitingForNetwork ? "Waiting for network" : (player.timeControlStatus == .playing ? "Playing" : "Paused / buffering"))
        return """
        Channel: \(currentChannel.title) • \(state)
        Video resolution: \(resolution)
        Reported stream bitrate: \(bitrate)
        Adaptive quality limit: \(String(format: "%.2f", item.preferredPeakBitRate / 1_000_000)) Mbps (preferred)
        Buffered ahead: \(String(format: "%.1f", buffered)) seconds
        Recent transfer throughput: \(speed)

        Recent events (latest at bottom)
        \(recentPlaybackEvents.joined(separator: "\n"))

        A stall notification does not identify its root cause. Throughput measures recent media downloads, not a full internet speed test.
        """
    }

    private func resetHealth() {
        lastPlayerTime = nil
        lastProgressAt = Date()
        loadedAt = Date()
        lastRecoveryAt = .distantPast
        recoveryDelay = 6
        consecutiveMissingVideoChecks = 0
        resetRecoveryWindow()
    }

    private func recordRecoveryAttempt(at date: Date) {
        if date.timeIntervalSince(recoveryWindowStartedAt) > 10 * 60 {
            recoveryWindowStartedAt = date
            recoveryAttemptsInWindow = 0
        }
        recoveryAttemptsInWindow += 1
    }

    private func resetRecoveryWindow() {
        recoveryWindowStartedAt = Date()
        recoveryAttemptsInWindow = 0
    }

    private func showStatus(_ text: String) {
        statusTimer?.invalidate()
        statusLabel.stringValue = "  \(text)  "
        statusLabel.isHidden = false
        statusTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.statusLabel.isHidden = true
            }
        }
    }

    private func showNowPlaying(_ channel: Channel) {
        nowPlayingTimer?.invalidate()
        nowPlayingLabel.stringValue = "  Now Playing: \(channel.title)  "
        nowPlayingLabel.isHidden = false
        nowPlayingTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.nowPlayingLabel.isHidden = true
            }
        }
    }

    private func markHealthy(_ reason: String) {
        healthStatusChanged?(true, "\(currentChannel.title): \(reason)")
    }

    private func markUnhealthy(_ reason: String) {
        healthStatusChanged?(false, "\(currentChannel.title): \(reason)")
    }

    private func nativeVideoIsVisible(on item: AVPlayerItem?) -> Bool {
        if playerLayer.isReadyForDisplay {
            return true
        }

        guard let item else {
            return false
        }

        let presentationSize = item.presentationSize
        return presentationSize.width > 16 && presentationSize.height > 16
    }
}
