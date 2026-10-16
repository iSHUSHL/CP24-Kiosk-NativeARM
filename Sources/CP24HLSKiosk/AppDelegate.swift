import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private struct RotationOption {
        let title: String
        let seconds: Int
    }

    private static let rotationPreferenceKey = "AutoSwitchIntervalSeconds"
    private static let launchAtLoginPreferenceKey = "LaunchAtLoginEnabled"
    private static let disableSleepPreferenceKey = "DisableSleepWhileStreaming"
    private static let restartOnUnhealthyPreferenceKey = "RestartOnUnhealthyEnabled"
    private static let dailyRestartPreferenceKey = "DailyRestartEnabled"
    private static let dailyRestartMinutePreferenceKey = "DailyRestartMinuteOfDay"
    private static let defaultRotationSeconds = 2 * 60 * 60
    private static let unhealthyRestartSeconds: TimeInterval = 10 * 60
    private static let defaultDailyRestartMinute = 4 * 60
    private static let failedChannelCooldownSeconds: TimeInterval = 60 * 60
    private static let rotationOptions = [
        RotationOption(title: "1 min", seconds: 60),
        RotationOption(title: "5 min", seconds: 5 * 60),
        RotationOption(title: "10 min", seconds: 10 * 60),
        RotationOption(title: "20 min", seconds: 20 * 60),
        RotationOption(title: "30 min", seconds: 30 * 60),
        RotationOption(title: "45 min", seconds: 45 * 60),
        RotationOption(title: "1 hour", seconds: 60 * 60),
        RotationOption(title: "1:30 min", seconds: 90 * 60),
        RotationOption(title: "2 hours", seconds: 2 * 60 * 60)
    ]
    private static let windowedAspectRatio: CGFloat = 16.0 / 9.0

    private let playerViewController = PlayerViewController()
    private var window: NSWindow?
    private var currentChannel: Channel = .cp24
    private var rotationTimer: Timer?
    private var healthRestartTimer: Timer?
    private var dailyRestartTimer: Timer?
    private var dashboardTimer: Timer?
    private var keyMonitor: Any?
    private var channelMenuItems: [Channel: NSMenuItem] = [:]
    private var shouldCenterAfterLeavingFullScreen = false
    private var aboutWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var dashboardWindow: NSWindow?
    private var releaseNotesWindow: NSWindow?
    private var releaseNotesArchiveWindow: NSWindow?
    private var safeguardsWindow: NSWindow?
    private var archiveStackView: NSStackView?
    private var archiveLoadMoreButton: NSButton?
    private var archiveVisibleCount = ReleaseNotes.archivePageSize
    private var rotationChannelButtons: [Channel: NSButton] = [:]
    private var rotationPopupButton: NSPopUpButton?
    private var launchAtLoginButton: NSButton?
    private var disableSleepButton: NSButton?
    private var restartOnUnhealthyButton: NSButton?
    private var dailyRestartButton: NSButton?
    private var dailyRestartPicker: NSDatePicker?
    private var dashboardChannelLabel: NSTextField?
    private var dashboardNetworkLabel: NSTextField?
    private var dashboardLastGoodLabel: NSTextField?
    private var dashboardLastHealthyLabel: NSTextField?
    private var dashboardNextRestartLabel: NSTextField?
    private var dashboardProtectionLabel: NSTextField?
    private var menuDashboardChannelLabel: NSTextField?
    private var menuDashboardNetworkLabel: NSTextField?
    private var menuDashboardLastGoodLabel: NSTextField?
    private var menuDashboardLastHealthyLabel: NSTextField?
    private var menuDashboardNextRestartLabel: NSTextField?
    private var menuDashboardProtectionLabel: NSTextField?
    private var dashboardMemoryLabel: NSTextField?
    private var dashboardDiskLabel: NSTextField?
    private var dashboardNetworkActivityLabel: NSTextField?
    private var dashboardAppMemoryLabel: NSTextField?
    private var dashboardCpuLabel: NSTextField?
    private var dashboardUptimeLabel: NSTextField?
    private var dashboardLogSizeLabel: NSTextField?
    private var dashboardAutoRotationLabel: NSTextField?
    private var memoryGraphView: DashboardGraphView?
    private var diskGraphView: DashboardGraphView?
    private var networkGraphView: DashboardGraphView?
    private var appMemoryGraphView: DashboardGraphView?
    private var cpuGraphView: DashboardGraphView?
    private var healthLogWindow: NSWindow?
    private var healthLogTextView: NSTextView?
    private var lastHealthyAt = Date()
    private var unhealthySince: Date?
    private var lastKnownGoodChannel: Channel = .cp24
    private var failedChannelCooldowns: [Channel: Date] = [:]
    private var isNetworkOnline = true
    private var networkStatusText = "Checking"
    private var isPlayerStoppedByClose = false
    private var isClosingPlayerWindow = false
    private var isTerminatingAfterFullScreenExit = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [
            Self.launchAtLoginPreferenceKey: true,
            Self.disableSleepPreferenceKey: true,
            Self.restartOnUnhealthyPreferenceKey: true,
            Self.dailyRestartPreferenceKey: false,
            Self.dailyRestartMinutePreferenceKey: Self.defaultDailyRestartMinute
        ])
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        NSApp.applicationIconImage = NSImage(named: "NewsTVKioskIcon")
        StreamHealthLog.append("App launched")
        CrashWatchdog.shared.start()
        playerViewController.fallbackRequested = { [weak self] _ in
            guard let self else { return }
            let failedChannel = self.currentChannel
            StreamHealthLog.append("Fallback requested after \(failedChannel.title) failed")
            self.markChannelUnavailable(failedChannel)
            if let target = self.nextAutomaticChannel() {
                self.select(target, userInitiated: false)
            } else {
                StreamHealthLog.append("No enabled fallback channel available; staying on current channel")
            }
        }
        playerViewController.healthStatusChanged = { [weak self] isHealthy, reason in
            self?.handlePlayerHealth(isHealthy: isHealthy, reason: reason)
        }
        NetworkMonitor.shared.statusChanged = { [weak self] isOnline, detail in
            self?.handleNetworkStatus(isOnline: isOnline, detail: detail)
        }
        NetworkMonitor.shared.start()

        applyLaunchAtLoginPreference(reportErrors: false)
        applySleepPreference()
        buildMenu()
        buildWindow()
        installKeyboardShortcuts()
        applyKioskPresentation()
        restartRotationTimer()
        startHealthRestartTimer()
        scheduleDailyRestart()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.enterFullScreen()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        StreamHealthLog.append("App terminating")
        CrashWatchdog.shared.markIntentionalShutdown()
        rotationTimer?.invalidate()
        healthRestartTimer?.invalidate()
        dailyRestartTimer?.invalidate()
        dashboardTimer?.invalidate()
        NetworkMonitor.shared.stop()
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        PowerManager.shared.setSleepDisabled(false)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        restorePlayerWindow()
        return true
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let window, window.styleMask.contains(.fullScreen), !isTerminatingAfterFullScreenExit else {
            prepareForDesktopExit()
            return .terminateNow
        }

        StreamHealthLog.append("Quit requested from full screen: exiting kiosk Space before terminating")
        isTerminatingAfterFullScreenExit = true
        isClosingPlayerWindow = false
        prepareForDesktopExit()
        window.toggleFullScreen(nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self, self.isTerminatingAfterFullScreenExit else { return }
            if self.window?.styleMask.contains(.fullScreen) == true {
                self.window?.toggleFullScreen(nil)
            } else {
                self.finishTerminatingAfterFullScreenExit()
            }
        }

        return .terminateCancel
    }

    @objc private func selectCP24() {
        select(.cp24, userInitiated: true)
    }

    @objc private func selectCitynews() {
        select(.citynews, userInitiated: true)
    }

    @objc private func selectGlobalToronto() {
        select(.globalToronto, userInitiated: true)
    }

    @objc private func rotateChannel() {
        guard isNetworkOnline, !isPlayerStoppedByClose else {
            StreamHealthLog.append("Auto-switch skipped: network offline")
            refreshDashboard()
            return
        }

        guard let target = nextAutomaticChannel() else {
            refreshDashboard()
            return
        }

        StreamHealthLog.append("Auto-switching from \(currentChannel.title) to \(target.title)")
        select(target, userInitiated: false)
    }

    @objc private func recoverStream() {
        StreamHealthLog.append("Manual stream reload requested")
        playerViewController.recoverNow(reason: "Manual reload")
    }

    @objc private func showAboutWindow() {
        if let aboutWindow {
            aboutWindow.center()
            aboutWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 470),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "About CP24 HLS Kiosk"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(named: "NewsTVKioskIcon") ?? NSApp.applicationIconImage
        iconView.imageScaling = .scaleProportionallyUpOrDown
        contentView.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: "CP24 HLS Kiosk")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.alignment = .center
        contentView.addSubview(titleLabel)

        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1"
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.translatesAutoresizingMaskIntoConstraints = false
        versionLabel.font = .systemFont(ofSize: 15, weight: .medium)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        contentView.addSubview(versionLabel)

        let madeByLabel = NSTextField(labelWithString: "Made by Igor Baran")
        madeByLabel.translatesAutoresizingMaskIntoConstraints = false
        madeByLabel.font = .systemFont(ofSize: 18, weight: .semibold)
        madeByLabel.alignment = .center
        contentView.addSubview(madeByLabel)

        let copyrightLabel = NSTextField(labelWithString: "Copyright © 2026 Igor Baran. All rights reserved.")
        copyrightLabel.translatesAutoresizingMaskIntoConstraints = false
        copyrightLabel.font = .systemFont(ofSize: 14)
        copyrightLabel.textColor = .secondaryLabelColor
        copyrightLabel.alignment = .center
        contentView.addSubview(copyrightLabel)

        let releaseNotesButton = NSButton(title: "Release Notes", target: self, action: #selector(showReleaseNotesWindow))
        releaseNotesButton.translatesAutoresizingMaskIntoConstraints = false
        releaseNotesButton.bezelStyle = .rounded
        contentView.addSubview(releaseNotesButton)

        let safeguardsButton = NSButton(title: "Safeguards", target: self, action: #selector(showSafeguardsWindow))
        safeguardsButton.translatesAutoresizingMaskIntoConstraints = false
        safeguardsButton.bezelStyle = .rounded
        contentView.addSubview(safeguardsButton)

        NSLayoutConstraint.activate([
            iconView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 34),
            iconView.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 168),
            iconView.heightAnchor.constraint(equalToConstant: 168),

            titleLabel.topAnchor.constraint(equalTo: iconView.bottomAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            versionLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 8),
            versionLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            versionLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            madeByLabel.topAnchor.constraint(equalTo: versionLabel.bottomAnchor, constant: 34),
            madeByLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            madeByLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            copyrightLabel.topAnchor.constraint(equalTo: madeByLabel.bottomAnchor, constant: 12),
            copyrightLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 32),
            copyrightLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -32),

            releaseNotesButton.topAnchor.constraint(equalTo: copyrightLabel.bottomAnchor, constant: 26),
            releaseNotesButton.trailingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: -8),
            releaseNotesButton.widthAnchor.constraint(equalToConstant: 150),

            safeguardsButton.topAnchor.constraint(equalTo: releaseNotesButton.topAnchor),
            safeguardsButton.leadingAnchor.constraint(equalTo: contentView.centerXAnchor, constant: 8),
            safeguardsButton.widthAnchor.constraint(equalToConstant: 150)
        ])

        aboutWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSafeguardsWindow() {
        if let safeguardsWindow {
            safeguardsWindow.center()
            safeguardsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 660),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Safeguards"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 620, height: 460)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.cornerRadius = 18
        headerView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.16).cgColor
        contentView.addSubview(headerView)

        let eyebrowLabel = NSTextField(labelWithString: "24/7 PROTECTION")
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = .controlAccentColor
        headerView.addSubview(eyebrowLabel)

        let titleLabel = NSTextField(labelWithString: "Safeguards")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 34, weight: .bold)
        headerView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Every protection currently built into CP24 HLS Kiosk")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        headerView.addSubview(subtitleLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 18, right: 14)
        scrollView.documentView = stackView

        for safeguard in Self.safeguards {
            stackView.addArrangedSubview(Self.safeguardCard(title: safeguard.title, body: safeguard.body))
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            headerView.heightAnchor.constraint(equalToConstant: 126),

            eyebrowLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            eyebrowLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            eyebrowLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: eyebrowLabel.bottomAnchor, constant: 7),
            titleLabel.leadingAnchor.constraint(equalTo: eyebrowLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: eyebrowLabel.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 5),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        safeguardsWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showReleaseNotesWindow() {
        if let releaseNotesWindow {
            releaseNotesWindow.center()
            releaseNotesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 640),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Release Notes"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 560, height: 460)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.cornerRadius = 18
        headerView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
        contentView.addSubview(headerView)

        let eyebrowLabel = NSTextField(labelWithString: "NEWS TV KIOSK")
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = .controlAccentColor
        headerView.addSubview(eyebrowLabel)

        let headerLabel = NSTextField(labelWithString: "What's New")
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        headerLabel.font = .systemFont(ofSize: 34, weight: .bold)
        headerView.addSubview(headerLabel)

        let subtitleLabel = NSTextField(labelWithString: "Latest 10 updates for CP24 HLS Kiosk")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        headerView.addSubview(subtitleLabel)

        let archiveButton = NSButton(title: "Archive", target: self, action: #selector(showReleaseNotesArchiveWindow))
        archiveButton.translatesAutoresizingMaskIntoConstraints = false
        archiveButton.bezelStyle = .rounded
        headerView.addSubview(archiveButton)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 18, right: 14)
        scrollView.documentView = stackView

        for note in ReleaseNotes.latest {
            stackView.addArrangedSubview(Self.releaseNoteCard(for: note))
        }

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            headerView.heightAnchor.constraint(equalToConstant: 126),

            eyebrowLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 20),
            eyebrowLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            eyebrowLabel.trailingAnchor.constraint(lessThanOrEqualTo: archiveButton.leadingAnchor, constant: -16),

            headerLabel.topAnchor.constraint(equalTo: eyebrowLabel.bottomAnchor, constant: 7),
            headerLabel.leadingAnchor.constraint(equalTo: eyebrowLabel.leadingAnchor),
            headerLabel.trailingAnchor.constraint(lessThanOrEqualTo: archiveButton.leadingAnchor, constant: -16),

            subtitleLabel.topAnchor.constraint(equalTo: headerLabel.bottomAnchor, constant: 5),
            subtitleLabel.leadingAnchor.constraint(equalTo: headerLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(lessThanOrEqualTo: archiveButton.leadingAnchor, constant: -16),

            archiveButton.centerYAnchor.constraint(equalTo: headerView.centerYAnchor),
            archiveButton.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),
            archiveButton.widthAnchor.constraint(equalToConstant: 104),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor)
        ])

        releaseNotesWindow = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showReleaseNotesArchiveWindow() {
        if let releaseNotesArchiveWindow {
            refreshReleaseNotesArchive()
            releaseNotesArchiveWindow.center()
            releaseNotesArchiveWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        archiveVisibleCount = ReleaseNotes.archivePageSize

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 620),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Release Notes Archive"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 560, height: 460)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Archive")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        contentView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Older releases load 20 at a time")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = .secondaryLabelColor
        contentView.addSubview(subtitleLabel)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        contentView.addSubview(scrollView)

        let stackView = NSStackView()
        stackView.translatesAutoresizingMaskIntoConstraints = false
        stackView.orientation = .vertical
        stackView.alignment = .width
        stackView.spacing = 14
        stackView.edgeInsets = NSEdgeInsets(top: 4, left: 2, bottom: 18, right: 14)
        scrollView.documentView = stackView
        archiveStackView = stackView

        let loadMoreButton = NSButton(title: "Load More", target: self, action: #selector(loadMoreReleaseNotesArchive))
        loadMoreButton.translatesAutoresizingMaskIntoConstraints = false
        loadMoreButton.bezelStyle = .rounded
        contentView.addSubview(loadMoreButton)
        archiveLoadMoreButton = loadMoreButton

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 24),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 28),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -28),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -18),
            scrollView.topAnchor.constraint(equalTo: subtitleLabel.bottomAnchor, constant: 18),
            scrollView.bottomAnchor.constraint(equalTo: loadMoreButton.topAnchor, constant: -14),

            stackView.leadingAnchor.constraint(equalTo: scrollView.contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: scrollView.contentView.trailingAnchor),
            stackView.topAnchor.constraint(equalTo: scrollView.contentView.topAnchor),
            stackView.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),

            loadMoreButton.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            loadMoreButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -18),
            loadMoreButton.widthAnchor.constraint(equalToConstant: 132)
        ])

        releaseNotesArchiveWindow = panel
        refreshReleaseNotesArchive()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func loadMoreReleaseNotesArchive() {
        archiveVisibleCount += ReleaseNotes.archivePageSize
        refreshReleaseNotesArchive()
    }

    private func refreshReleaseNotesArchive() {
        guard let archiveStackView else { return }
        for view in archiveStackView.arrangedSubviews {
            archiveStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let notes = ReleaseNotes.archivePage(count: archiveVisibleCount)
        if notes.isEmpty {
            archiveStackView.addArrangedSubview(Self.emptyArchiveView())
        } else {
            for note in notes {
                archiveStackView.addArrangedSubview(Self.releaseNoteCard(for: note))
            }
        }

        archiveLoadMoreButton?.isHidden = archiveVisibleCount >= ReleaseNotes.archive.count
    }

    private static let safeguards: [(title: String, body: String)] = [
        (
            "Crash Watchdog",
            "A separate monitor watches the app process and reopens CP24 HLS Kiosk after an unexpected crash or disappearance. Normal Quit is treated as intentional and will not restart the app."
        ),
        (
            "Unhealthy Stream Relaunch",
            "If playback remains unhealthy for 10 minutes, the app relaunches itself cleanly to recover from stuck players or long-running stream failures."
        ),
        (
            "Smart Stream Recovery",
            "The player checks stream health every 15 seconds and reloads when playback stalls, fails, pauses too long, buffers too long, loses video, or stops progressing."
        ),
        (
            "Fallback Channel Switching",
            "After repeated recovery failures on one channel, the app switches to another enabled, available channel automatically so the kiosk keeps showing live news."
        ),
        (
            "Last Known Good Channel",
            "When a channel repeatedly fails, it is held out of automatic rotation for one hour so the app can stay longer on the channel that was last working."
        ),
        (
            "Network Awareness",
            "The app watches macOS network status, shows Waiting for network when offline, pauses stream health relaunch decisions while offline, and recovers when internet returns."
        ),
        (
            "Settings Status Dashboard",
            "Settings includes a live dashboard for current channel, network status, last known good channel, last healthy playback time, next restart, and active protection state."
        ),
        (
            "System Monitoring Dashboard",
            "The Dashboard menu shows live system metrics including RAM, disk space, CPU load, app memory, Mac uptime, health log size, and graph trends."
        ),
        (
            "Daily Auto-Restart",
            "Settings can schedule one clean restart per day at the selected time, useful for long 24/7 runs."
        ),
        (
            "Launch at Login",
            "Settings can register CP24 HLS Kiosk to start automatically when the Mac logs in."
        ),
        (
            "Disable Sleep While Streaming",
            "The app can hold macOS power assertions that prevent system sleep and display sleep while the player is active."
        ),
        (
            "Stream Health Log",
            "A persistent log records launches, stream loads, recoveries, stalls, failures, fallback switches, relaunches, crash watchdog activity, close/reopen events, and power/login status."
        ),
        (
            "30-Day Log Retention",
            "Health log entries older than 30 days are automatically pruned so diagnostics stay useful without growing forever."
        ),
        (
            "No Captions Guard",
            "Native playback disables captions, subtitles, and text tracks whenever streams load."
        ),
        (
            "Clean Channel Switching",
            "Switching channels stops the previous player path first so old audio does not continue under the new stream."
        ),
        (
            "Close Button Protection",
            "Closing the player stops audio and video, releases sleep/kiosk presentation mode, exits full screen before hiding the window, and keeps the app menu active."
        ),
        (
            "Dock Reopen Recovery",
            "Clicking the Dock icon after closing the player reopens full screen and starts the current channel again."
        ),
        (
            "Kiosk Presentation Mode",
            "Full-screen playback auto-hides the Dock and menu bar and limits process switching while the kiosk player is active."
        ),
        (
            "Auto Channel Rotation",
            "Choose which channels participate in automatic rotation and fallback, with a saved interval from 1 minute to 2 hours. Uncheck all to stop automatic switching."
        ),
        (
            "Manual Recovery Shortcut",
            "Command-R reloads the current stream, while number keys 1, 2, and 3 switch directly to CP24, CityNews, and Global News Toronto."
        ),
        (
            "Now Playing Overlay",
            "A small on-screen Now Playing overlay appears on channel load or switch and disappears after a few seconds."
        ),
        (
            "Apple Silicon Build",
            "The packaged app is built natively for Apple Silicon Macs (arm64)."
        )
    ]

    private static func safeguardCard(title: String, body: String) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let accent = NSView()
        accent.translatesAutoresizingMaskIntoConstraints = false
        accent.wantsLayer = true
        accent.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.85).cgColor
        accent.layer?.cornerRadius = 2
        card.addSubview(accent)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 15, weight: .bold)
        titleLabel.textColor = .labelColor
        card.addSubview(titleLabel)

        let bodyLabel = NSTextField(labelWithString: body)
        bodyLabel.translatesAutoresizingMaskIntoConstraints = false
        bodyLabel.font = .systemFont(ofSize: 13)
        bodyLabel.textColor = .secondaryLabelColor
        bodyLabel.maximumNumberOfLines = 0
        bodyLabel.lineBreakMode = .byWordWrapping
        card.addSubview(bodyLabel)

        NSLayoutConstraint.activate([
            accent.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            accent.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            accent.widthAnchor.constraint(equalToConstant: 4),
            accent.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: accent.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 7),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private static func dashboardCaption(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 11, weight: .bold)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func dashboardValue() -> NSTextField {
        let label = NSTextField(labelWithString: "...")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func dashboardMetricValue() -> NSTextField {
        let label = NSTextField(labelWithString: "...")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 18, weight: .bold)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func dashboardGlassValue(size: CGFloat) -> NSTextField {
        let label = NSTextField(labelWithString: "...")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: size, weight: .bold)
        label.textColor = .white
        label.lineBreakMode = .byTruncatingTail
        return label
    }

    private static func dashboardGlassCard(title: String, valueLabel: NSTextField, accent: NSColor) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 16
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.09).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.16).cgColor

        let accentBar = NSView()
        accentBar.translatesAutoresizingMaskIntoConstraints = false
        accentBar.wantsLayer = true
        accentBar.layer?.cornerRadius = 3
        accentBar.layer?.backgroundColor = accent.withAlphaComponent(0.95).cgColor
        card.addSubview(accentBar)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        NSLayoutConstraint.activate([
            accentBar.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            accentBar.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            accentBar.widthAnchor.constraint(equalToConstant: 5),
            accentBar.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -18),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            titleLabel.leadingAnchor.constraint(equalTo: accentBar.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14)
        ])

        return card
    }

    private static func controlCenterCard(title: String, valueLabel: NSTextField, graphView: DashboardGraphView?, accent: NSColor, symbolName: String) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 18
        card.layer?.backgroundColor = NSColor(calibratedRed: 0.115, green: 0.125, blue: 0.155, alpha: 0.94).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor

        let topLine = NSView()
        topLine.translatesAutoresizingMaskIntoConstraints = false
        topLine.wantsLayer = true
        topLine.layer?.cornerRadius = 2
        topLine.layer?.backgroundColor = accent.withAlphaComponent(0.95).cgColor
        card.addSubview(topLine)

        let iconPlate = NSView()
        iconPlate.translatesAutoresizingMaskIntoConstraints = false
        iconPlate.wantsLayer = true
        iconPlate.layer?.cornerRadius = 13
        iconPlate.layer?.backgroundColor = accent.withAlphaComponent(0.18).cgColor
        iconPlate.layer?.borderWidth = 1
        iconPlate.layer?.borderColor = accent.withAlphaComponent(0.28).cgColor
        card.addSubview(iconPlate)

        let iconView = NSImageView()
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        iconView.contentTintColor = .white
        iconView.imageScaling = .scaleProportionallyDown
        iconPlate.addSubview(iconView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.56)
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        let visualPlate = NSView()
        visualPlate.translatesAutoresizingMaskIntoConstraints = false
        visualPlate.wantsLayer = true
        visualPlate.layer?.cornerRadius = 14
        visualPlate.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.18).cgColor
        visualPlate.layer?.borderWidth = 1
        visualPlate.layer?.borderColor = NSColor.white.withAlphaComponent(0.08).cgColor
        card.addSubview(visualPlate)

        var constraints = [
            card.heightAnchor.constraint(equalToConstant: 82),

            topLine.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            topLine.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            topLine.topAnchor.constraint(equalTo: card.topAnchor),
            topLine.heightAnchor.constraint(equalToConstant: 3),

            iconPlate.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            iconPlate.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            iconPlate.widthAnchor.constraint(equalToConstant: 44),
            iconPlate.heightAnchor.constraint(equalToConstant: 44),

            iconView.centerXAnchor.constraint(equalTo: iconPlate.centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: iconPlate.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 21),
            iconView.heightAnchor.constraint(equalToConstant: 21),

            visualPlate.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            visualPlate.centerYAnchor.constraint(equalTo: card.centerYAnchor),
            visualPlate.widthAnchor.constraint(equalToConstant: 156),
            visualPlate.heightAnchor.constraint(equalToConstant: 50),

            titleLabel.leadingAnchor.constraint(equalTo: iconPlate.trailingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: visualPlate.leadingAnchor, constant: -16),
            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),

            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            valueLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: card.bottomAnchor, constant: -14)
        ]

        if let graphView {
            graphView.translatesAutoresizingMaskIntoConstraints = false
            visualPlate.addSubview(graphView)
            constraints += [
                graphView.leadingAnchor.constraint(equalTo: visualPlate.leadingAnchor, constant: 8),
                graphView.trailingAnchor.constraint(equalTo: visualPlate.trailingAnchor, constant: -8),
                graphView.topAnchor.constraint(equalTo: visualPlate.topAnchor, constant: 7),
                graphView.bottomAnchor.constraint(equalTo: visualPlate.bottomAnchor, constant: -7)
            ]
        } else {
            let bars = NSStackView()
            bars.translatesAutoresizingMaskIntoConstraints = false
            bars.orientation = .vertical
            bars.alignment = .trailing
            bars.distribution = .equalSpacing
            bars.spacing = 6
            visualPlate.addSubview(bars)

            for width in [112, 82, 126] {
                let bar = NSView()
                bar.translatesAutoresizingMaskIntoConstraints = false
                bar.wantsLayer = true
                bar.layer?.cornerRadius = 3
                bar.layer?.backgroundColor = accent.withAlphaComponent(0.42).cgColor
                bars.addArrangedSubview(bar)
                constraints += [
                    bar.widthAnchor.constraint(equalToConstant: CGFloat(width)),
                    bar.heightAnchor.constraint(equalToConstant: 6)
                ]
            }

            constraints += [
                bars.trailingAnchor.constraint(equalTo: visualPlate.trailingAnchor, constant: -14),
                bars.centerYAnchor.constraint(equalTo: visualPlate.centerYAnchor),
                bars.heightAnchor.constraint(equalToConstant: 30)
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return card
    }

    private static func monitorCard(title: String, valueLabel: NSTextField, graphView: DashboardGraphView?, accent: NSColor) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.cornerRadius = 14
        card.layer?.backgroundColor = NSColor.white.withAlphaComponent(0.085).cgColor
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.white.withAlphaComponent(0.14).cgColor

        let accentView = NSView()
        accentView.translatesAutoresizingMaskIntoConstraints = false
        accentView.wantsLayer = true
        accentView.layer?.cornerRadius = 3
        accentView.layer?.backgroundColor = accent.withAlphaComponent(0.92).cgColor
        card.addSubview(accentView)

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 11, weight: .bold)
        titleLabel.textColor = NSColor.white.withAlphaComponent(0.62)
        titleLabel.lineBreakMode = .byTruncatingTail
        card.addSubview(titleLabel)
        card.addSubview(valueLabel)

        let footerLabel = NSTextField(labelWithString: graphView == nil ? "Live system status" : "Live trend")
        footerLabel.translatesAutoresizingMaskIntoConstraints = false
        footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        footerLabel.textColor = NSColor.white.withAlphaComponent(0.42)
        card.addSubview(footerLabel)

        var constraints = [
            accentView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            accentView.topAnchor.constraint(equalTo: card.topAnchor, constant: 18),
            accentView.widthAnchor.constraint(equalToConstant: 5),
            accentView.heightAnchor.constraint(equalToConstant: 28),

            titleLabel.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: accentView.trailingAnchor, constant: 12),
            titleLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),

            valueLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            valueLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            valueLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            footerLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            footerLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            footerLabel.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14)
        ]

        if let graphView {
            graphView.translatesAutoresizingMaskIntoConstraints = false
            card.addSubview(graphView)
            constraints += [
                graphView.topAnchor.constraint(equalTo: valueLabel.bottomAnchor, constant: 14),
                graphView.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 14),
                graphView.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -14),
                graphView.bottomAnchor.constraint(equalTo: footerLabel.topAnchor, constant: -10),
                graphView.heightAnchor.constraint(greaterThanOrEqualToConstant: 52)
            ]
        } else {
            constraints += [
                valueLabel.bottomAnchor.constraint(lessThanOrEqualTo: footerLabel.topAnchor, constant: -18)
            ]
        }

        NSLayoutConstraint.activate(constraints)
        return card
    }

    private static func releaseNoteCard(for note: ReleaseNote) -> NSView {
        let card = NSView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 12
        card.layer?.borderWidth = 1
        card.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let versionBadge = NSTextField(labelWithString: note.version)
        versionBadge.translatesAutoresizingMaskIntoConstraints = false
        versionBadge.font = .systemFont(ofSize: 15, weight: .bold)
        versionBadge.textColor = .controlAccentColor
        card.addSubview(versionBadge)

        let dateLabel = NSTextField(labelWithString: note.date)
        dateLabel.translatesAutoresizingMaskIntoConstraints = false
        dateLabel.font = .systemFont(ofSize: 12, weight: .medium)
        dateLabel.textColor = .secondaryLabelColor
        dateLabel.alignment = .right
        card.addSubview(dateLabel)

        let changesStack = NSStackView()
        changesStack.translatesAutoresizingMaskIntoConstraints = false
        changesStack.orientation = .vertical
        changesStack.alignment = .leading
        changesStack.spacing = 7
        card.addSubview(changesStack)

        for change in note.changes {
            let item = NSTextField(labelWithString: "• \(change)")
            item.translatesAutoresizingMaskIntoConstraints = false
            item.font = .systemFont(ofSize: 13)
            item.textColor = .labelColor
            item.maximumNumberOfLines = 0
            item.lineBreakMode = .byWordWrapping
            changesStack.addArrangedSubview(item)
        }

        NSLayoutConstraint.activate([
            versionBadge.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            versionBadge.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),

            dateLabel.centerYAnchor.constraint(equalTo: versionBadge.centerYAnchor),
            dateLabel.leadingAnchor.constraint(greaterThanOrEqualTo: versionBadge.trailingAnchor, constant: 12),
            dateLabel.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),

            changesStack.topAnchor.constraint(equalTo: versionBadge.bottomAnchor, constant: 12),
            changesStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 18),
            changesStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -18),
            changesStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16)
        ])

        return card
    }

    private static func emptyArchiveView() -> NSView {
        let view = NSView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        view.layer?.cornerRadius = 12
        view.layer?.borderWidth = 1
        view.layer?.borderColor = NSColor.separatorColor.withAlphaComponent(0.35).cgColor

        let label = NSTextField(labelWithString: "No archived release notes yet.")
        label.translatesAutoresizingMaskIntoConstraints = false
        label.font = .systemFont(ofSize: 15, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        view.addSubview(label)

        NSLayoutConstraint.activate([
            view.heightAnchor.constraint(equalToConstant: 86),
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 20),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -20)
        ])

        return view
    }

    @objc private func showDashboardWindow() {
        if let dashboardWindow {
            refreshDashboard()
            dashboardWindow.center()
            dashboardWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 820),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Live Dashboard"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 1060, height: 820)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor(calibratedRed: 0.055, green: 0.065, blue: 0.095, alpha: 1).cgColor
        panel.contentView = contentView

        let headerView = NSView()
        headerView.translatesAutoresizingMaskIntoConstraints = false
        headerView.wantsLayer = true
        headerView.layer?.cornerRadius = 22
        headerView.layer?.backgroundColor = NSColor(calibratedRed: 0.10, green: 0.12, blue: 0.20, alpha: 0.92).cgColor
        headerView.layer?.borderWidth = 1
        headerView.layer?.borderColor = NSColor.white.withAlphaComponent(0.12).cgColor
        contentView.addSubview(headerView)

        let eyebrowLabel = NSTextField(labelWithString: "NEWS TV KIOSK")
        eyebrowLabel.translatesAutoresizingMaskIntoConstraints = false
        eyebrowLabel.font = .systemFont(ofSize: 12, weight: .bold)
        eyebrowLabel.textColor = NSColor(calibratedRed: 0.55, green: 0.82, blue: 1.0, alpha: 1)
        headerView.addSubview(eyebrowLabel)

        let titleLabel = NSTextField(labelWithString: "Live Dashboard")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 30, weight: .bold)
        titleLabel.textColor = .white
        headerView.addSubview(titleLabel)

        let subtitleLabel = NSTextField(labelWithString: "Streams, safeguards, and system health at a glance")
        subtitleLabel.translatesAutoresizingMaskIntoConstraints = false
        subtitleLabel.font = .systemFont(ofSize: 14, weight: .medium)
        subtitleLabel.textColor = NSColor.white.withAlphaComponent(0.70)
        headerView.addSubview(subtitleLabel)

        let liveBadge = NSView()
        liveBadge.translatesAutoresizingMaskIntoConstraints = false
        liveBadge.wantsLayer = true
        liveBadge.layer?.backgroundColor = NSColor.systemGreen.withAlphaComponent(0.72).cgColor
        liveBadge.layer?.cornerRadius = 12
        headerView.addSubview(liveBadge)

        let liveBadgeLabel = NSTextField(labelWithString: "LIVE")
        liveBadgeLabel.translatesAutoresizingMaskIntoConstraints = false
        liveBadgeLabel.font = .systemFont(ofSize: 13, weight: .bold)
        liveBadgeLabel.textColor = .white
        liveBadgeLabel.alignment = .center
        liveBadge.addSubview(liveBadgeLabel)

        let dashboardGrid = NSStackView()
        dashboardGrid.translatesAutoresizingMaskIntoConstraints = false
        dashboardGrid.orientation = .vertical
        dashboardGrid.alignment = .width
        dashboardGrid.distribution = .fill
        dashboardGrid.spacing = 10
        contentView.addSubview(dashboardGrid)

        func dashboardRow(_ cards: [NSView]) -> NSStackView {
            let row = NSStackView()
            row.translatesAutoresizingMaskIntoConstraints = false
            row.orientation = .horizontal
            row.alignment = .height
            row.distribution = .fillEqually
            row.spacing = 10
            cards.forEach { row.addArrangedSubview($0) }
            return row
        }

        let channelValue = Self.dashboardGlassValue(size: 21)
        menuDashboardChannelLabel = channelValue

        let networkValue = Self.dashboardGlassValue(size: 21)
        menuDashboardNetworkLabel = networkValue

        let protectionValue = Self.dashboardGlassValue(size: 21)
        menuDashboardProtectionLabel = protectionValue

        let nextRestartValue = Self.dashboardGlassValue(size: 16)
        menuDashboardNextRestartLabel = nextRestartValue

        let memoryValue = Self.dashboardGlassValue(size: 17)
        let memoryGraph = DashboardGraphView(strokeColor: .systemGreen)
        dashboardMemoryLabel = memoryValue
        memoryGraphView = memoryGraph

        let diskValue = Self.dashboardGlassValue(size: 17)
        let diskGraph = DashboardGraphView(strokeColor: .systemBlue)
        dashboardDiskLabel = diskValue
        diskGraphView = diskGraph

        let networkActivityValue = Self.dashboardGlassValue(size: 17)
        let networkActivityGraph = DashboardGraphView(strokeColor: .systemTeal)
        dashboardNetworkActivityLabel = networkActivityValue
        networkGraphView = networkActivityGraph

        let cpuValue = Self.dashboardGlassValue(size: 17)
        let cpuGraph = DashboardGraphView(strokeColor: .systemOrange)
        dashboardCpuLabel = cpuValue
        cpuGraphView = cpuGraph

        let appMemoryValue = Self.dashboardGlassValue(size: 17)
        let appMemoryGraph = DashboardGraphView(strokeColor: .systemPurple)
        dashboardAppMemoryLabel = appMemoryValue
        appMemoryGraphView = appMemoryGraph

        let uptimeValue = Self.dashboardGlassValue(size: 17)
        dashboardUptimeLabel = uptimeValue

        let lastGoodValue = Self.dashboardGlassValue(size: 17)
        menuDashboardLastGoodLabel = lastGoodValue

        let lastHealthyValue = Self.dashboardGlassValue(size: 17)
        menuDashboardLastHealthyLabel = lastHealthyValue

        let logSizeValue = Self.dashboardGlassValue(size: 17)
        dashboardLogSizeLabel = logSizeValue

        let autoRotationValue = Self.dashboardGlassValue(size: 17)
        dashboardAutoRotationLabel = autoRotationValue

        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "Current Channel", valueLabel: channelValue, graphView: nil, accent: .systemRed, symbolName: "tv"),
            Self.controlCenterCard(title: "Network", valueLabel: networkValue, graphView: nil, accent: .systemTeal, symbolName: "wifi")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "Protection", valueLabel: protectionValue, graphView: nil, accent: .systemGreen, symbolName: "shield"),
            Self.controlCenterCard(title: "Next Restart", valueLabel: nextRestartValue, graphView: nil, accent: .systemPurple, symbolName: "clock")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "System RAM", valueLabel: memoryValue, graphView: memoryGraph, accent: .systemGreen, symbolName: "memorychip"),
            Self.controlCenterCard(title: "Disk Space", valueLabel: diskValue, graphView: diskGraph, accent: .systemBlue, symbolName: "internaldrive")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "Network Activity", valueLabel: networkActivityValue, graphView: networkActivityGraph, accent: .systemTeal, symbolName: "network"),
            Self.controlCenterCard(title: "CPU Load", valueLabel: cpuValue, graphView: cpuGraph, accent: .systemOrange, symbolName: "speedometer")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "App Memory", valueLabel: appMemoryValue, graphView: appMemoryGraph, accent: .systemPurple, symbolName: "app"),
            Self.controlCenterCard(title: "Mac Uptime", valueLabel: uptimeValue, graphView: nil, accent: .systemIndigo, symbolName: "timer")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "Last Good Channel", valueLabel: lastGoodValue, graphView: nil, accent: .systemPink, symbolName: "checkmark.circle"),
            Self.controlCenterCard(title: "Last Healthy", valueLabel: lastHealthyValue, graphView: nil, accent: .systemMint, symbolName: "heart")
        ]))
        dashboardGrid.addArrangedSubview(dashboardRow([
            Self.controlCenterCard(title: "Health Log", valueLabel: logSizeValue, graphView: nil, accent: .systemYellow, symbolName: "doc.text"),
            Self.controlCenterCard(title: "Auto Rotation", valueLabel: autoRotationValue, graphView: nil, accent: .systemBlue, symbolName: "repeat")
        ]))

        NSLayoutConstraint.activate([
            headerView.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            headerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 22),
            headerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -22),
            headerView.heightAnchor.constraint(equalToConstant: 98),

            eyebrowLabel.topAnchor.constraint(equalTo: headerView.topAnchor, constant: 15),
            eyebrowLabel.leadingAnchor.constraint(equalTo: headerView.leadingAnchor, constant: 24),
            eyebrowLabel.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -24),

            titleLabel.topAnchor.constraint(equalTo: eyebrowLabel.bottomAnchor, constant: 5),
            titleLabel.leadingAnchor.constraint(equalTo: eyebrowLabel.leadingAnchor),
            titleLabel.trailingAnchor.constraint(equalTo: eyebrowLabel.trailingAnchor),

            subtitleLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 2),
            subtitleLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            subtitleLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),

            liveBadge.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            liveBadge.trailingAnchor.constraint(equalTo: headerView.trailingAnchor, constant: -26),
            liveBadge.widthAnchor.constraint(equalToConstant: 72),
            liveBadge.heightAnchor.constraint(equalToConstant: 26),

            liveBadgeLabel.centerXAnchor.constraint(equalTo: liveBadge.centerXAnchor),
            liveBadgeLabel.centerYAnchor.constraint(equalTo: liveBadge.centerYAnchor),
            liveBadgeLabel.leadingAnchor.constraint(equalTo: liveBadge.leadingAnchor, constant: 8),
            liveBadgeLabel.trailingAnchor.constraint(equalTo: liveBadge.trailingAnchor, constant: -8),

            dashboardGrid.topAnchor.constraint(equalTo: headerView.bottomAnchor, constant: 18),
            dashboardGrid.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            dashboardGrid.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            dashboardGrid.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor, constant: -24)
        ])

        dashboardWindow = panel
        startDashboardTimer()
        refreshDashboard()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettingsWindow() {
        if let settingsWindow {
            updateSettingsControls()
            settingsWindow.center()
            settingsWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 720),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Settings"
        panel.isReleasedWhenClosed = false
        panel.level = .floating

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Preferences")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 22, weight: .bold)
        contentView.addSubview(titleLabel)

        let dashboardView = NSView()
        dashboardView.translatesAutoresizingMaskIntoConstraints = false
        dashboardView.wantsLayer = true
        dashboardView.layer?.cornerRadius = 14
        dashboardView.layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.12).cgColor
        dashboardView.layer?.borderWidth = 1
        dashboardView.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.22).cgColor
        contentView.addSubview(dashboardView)

        let dashboardTitle = NSTextField(labelWithString: "Live Dashboard")
        dashboardTitle.translatesAutoresizingMaskIntoConstraints = false
        dashboardTitle.font = .systemFont(ofSize: 16, weight: .bold)
        dashboardView.addSubview(dashboardTitle)

        let channelCaption = Self.dashboardCaption("Current Channel")
        let channelValue = Self.dashboardValue()
        dashboardChannelLabel = channelValue
        dashboardView.addSubview(channelCaption)
        dashboardView.addSubview(channelValue)

        let networkCaption = Self.dashboardCaption("Network")
        let networkValue = Self.dashboardValue()
        dashboardNetworkLabel = networkValue
        dashboardView.addSubview(networkCaption)
        dashboardView.addSubview(networkValue)

        let lastGoodCaption = Self.dashboardCaption("Last Good Channel")
        let lastGoodValue = Self.dashboardValue()
        dashboardLastGoodLabel = lastGoodValue
        dashboardView.addSubview(lastGoodCaption)
        dashboardView.addSubview(lastGoodValue)

        let lastHealthyCaption = Self.dashboardCaption("Last Healthy")
        let lastHealthyValue = Self.dashboardValue()
        dashboardLastHealthyLabel = lastHealthyValue
        dashboardView.addSubview(lastHealthyCaption)
        dashboardView.addSubview(lastHealthyValue)

        let nextRestartCaption = Self.dashboardCaption("Next Restart")
        let nextRestartValue = Self.dashboardValue()
        dashboardNextRestartLabel = nextRestartValue
        dashboardView.addSubview(nextRestartCaption)
        dashboardView.addSubview(nextRestartValue)

        let protectionCaption = Self.dashboardCaption("Protection")
        let protectionValue = Self.dashboardValue()
        dashboardProtectionLabel = protectionValue
        dashboardView.addSubview(protectionCaption)
        dashboardView.addSubview(protectionValue)

        let autoSwitchLabel = NSTextField(labelWithString: "Auto switch channels every")
        autoSwitchLabel.translatesAutoresizingMaskIntoConstraints = false
        autoSwitchLabel.font = .systemFont(ofSize: 14, weight: .medium)
        contentView.addSubview(autoSwitchLabel)

        let popup = NSPopUpButton(frame: .zero, pullsDown: false)
        popup.translatesAutoresizingMaskIntoConstraints = false
        popup.target = self
        popup.action = #selector(rotationPopupChanged(_:))
        for option in Self.rotationOptions {
            popup.addItem(withTitle: option.title)
            popup.lastItem?.representedObject = option.seconds
        }
        contentView.addSubview(popup)
        rotationPopupButton = popup

        let rotationLabel = NSTextField(labelWithString: "Include in automatic rotation and fallback:")
        rotationLabel.font = .systemFont(ofSize: 13, weight: .medium)
        let channelRow = NSStackView()
        channelRow.orientation = .horizontal
        channelRow.spacing = 18
        for (index, channel) in Channel.allCases.enumerated() {
            let button = NSButton(checkboxWithTitle: channel.title, target: self, action: #selector(rotationChannelChanged(_:)))
            button.tag = index
            rotationChannelButtons[channel] = button
            channelRow.addArrangedSubview(button)
        }
        let rotationHint = NSTextField(labelWithString: "Uncheck all to stop automatic switching. Manual channel selection stays available.")
        rotationHint.font = .systemFont(ofSize: 11)
        rotationHint.textColor = .secondaryLabelColor
        let rotationSelection = NSStackView(views: [rotationLabel, channelRow, rotationHint])
        rotationSelection.orientation = .vertical
        rotationSelection.alignment = .leading
        rotationSelection.spacing = 8
        rotationSelection.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(rotationSelection)

        let launchButton = NSButton(checkboxWithTitle: "Launch CP24 HLS Kiosk at login", target: self, action: #selector(launchAtLoginChanged(_:)))
        launchButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(launchButton)
        launchAtLoginButton = launchButton

        let sleepButton = NSButton(checkboxWithTitle: "Disable sleep while streaming", target: self, action: #selector(disableSleepChanged(_:)))
        sleepButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sleepButton)
        disableSleepButton = sleepButton

        let restartButton = NSButton(checkboxWithTitle: "Restart app if stream is unhealthy for 10 minutes", target: self, action: #selector(restartOnUnhealthyChanged(_:)))
        restartButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(restartButton)
        restartOnUnhealthyButton = restartButton

        let dailyButton = NSButton(checkboxWithTitle: "Daily auto-restart at", target: self, action: #selector(dailyRestartChanged(_:)))
        dailyButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(dailyButton)
        dailyRestartButton = dailyButton

        let dailyPicker = NSDatePicker()
        dailyPicker.translatesAutoresizingMaskIntoConstraints = false
        dailyPicker.datePickerElements = [.hourMinute]
        dailyPicker.datePickerStyle = .textFieldAndStepper
        dailyPicker.datePickerMode = .single
        dailyPicker.target = self
        dailyPicker.action = #selector(dailyRestartTimeChanged(_:))
        contentView.addSubview(dailyPicker)
        dailyRestartPicker = dailyPicker

        let healthLogButton = NSButton(title: "View Stream Health Log", target: self, action: #selector(showHealthLogWindow))
        healthLogButton.translatesAutoresizingMaskIntoConstraints = false
        healthLogButton.bezelStyle = .rounded
        contentView.addSubview(healthLogButton)

        let noteLabel = NSTextField(labelWithString: "Reliability settings are saved automatically.")
        noteLabel.translatesAutoresizingMaskIntoConstraints = false
        noteLabel.font = .systemFont(ofSize: 13)
        noteLabel.textColor = .secondaryLabelColor
        contentView.addSubview(noteLabel)

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 28),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            titleLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            dashboardView.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 18),
            dashboardView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            dashboardView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),
            dashboardView.heightAnchor.constraint(equalToConstant: 178),

            dashboardTitle.topAnchor.constraint(equalTo: dashboardView.topAnchor, constant: 18),
            dashboardTitle.leadingAnchor.constraint(equalTo: dashboardView.leadingAnchor, constant: 20),
            dashboardTitle.trailingAnchor.constraint(equalTo: dashboardView.trailingAnchor, constant: -20),

            channelCaption.topAnchor.constraint(equalTo: dashboardTitle.bottomAnchor, constant: 18),
            channelCaption.leadingAnchor.constraint(equalTo: dashboardTitle.leadingAnchor),
            channelCaption.widthAnchor.constraint(equalTo: dashboardView.widthAnchor, multiplier: 0.28),
            channelValue.topAnchor.constraint(equalTo: channelCaption.bottomAnchor, constant: 4),
            channelValue.leadingAnchor.constraint(equalTo: channelCaption.leadingAnchor),
            channelValue.trailingAnchor.constraint(equalTo: channelCaption.trailingAnchor),

            networkCaption.topAnchor.constraint(equalTo: channelCaption.topAnchor),
            networkCaption.leadingAnchor.constraint(equalTo: channelCaption.trailingAnchor, constant: 28),
            networkCaption.widthAnchor.constraint(equalTo: dashboardView.widthAnchor, multiplier: 0.28),
            networkValue.topAnchor.constraint(equalTo: networkCaption.bottomAnchor, constant: 4),
            networkValue.leadingAnchor.constraint(equalTo: networkCaption.leadingAnchor),
            networkValue.trailingAnchor.constraint(equalTo: networkCaption.trailingAnchor),

            lastGoodCaption.topAnchor.constraint(equalTo: channelCaption.topAnchor),
            lastGoodCaption.leadingAnchor.constraint(equalTo: networkCaption.trailingAnchor, constant: 28),
            lastGoodCaption.trailingAnchor.constraint(equalTo: dashboardView.trailingAnchor, constant: -20),
            lastGoodValue.topAnchor.constraint(equalTo: lastGoodCaption.bottomAnchor, constant: 4),
            lastGoodValue.leadingAnchor.constraint(equalTo: lastGoodCaption.leadingAnchor),
            lastGoodValue.trailingAnchor.constraint(equalTo: lastGoodCaption.trailingAnchor),

            lastHealthyCaption.topAnchor.constraint(equalTo: channelValue.bottomAnchor, constant: 22),
            lastHealthyCaption.leadingAnchor.constraint(equalTo: channelCaption.leadingAnchor),
            lastHealthyCaption.trailingAnchor.constraint(equalTo: channelCaption.trailingAnchor),
            lastHealthyValue.topAnchor.constraint(equalTo: lastHealthyCaption.bottomAnchor, constant: 4),
            lastHealthyValue.leadingAnchor.constraint(equalTo: lastHealthyCaption.leadingAnchor),
            lastHealthyValue.trailingAnchor.constraint(equalTo: lastHealthyCaption.trailingAnchor),

            nextRestartCaption.topAnchor.constraint(equalTo: lastHealthyCaption.topAnchor),
            nextRestartCaption.leadingAnchor.constraint(equalTo: networkCaption.leadingAnchor),
            nextRestartCaption.trailingAnchor.constraint(equalTo: networkCaption.trailingAnchor),
            nextRestartValue.topAnchor.constraint(equalTo: nextRestartCaption.bottomAnchor, constant: 4),
            nextRestartValue.leadingAnchor.constraint(equalTo: nextRestartCaption.leadingAnchor),
            nextRestartValue.trailingAnchor.constraint(equalTo: nextRestartCaption.trailingAnchor),

            protectionCaption.topAnchor.constraint(equalTo: lastHealthyCaption.topAnchor),
            protectionCaption.leadingAnchor.constraint(equalTo: lastGoodCaption.leadingAnchor),
            protectionCaption.trailingAnchor.constraint(equalTo: lastGoodCaption.trailingAnchor),
            protectionValue.topAnchor.constraint(equalTo: protectionCaption.bottomAnchor, constant: 4),
            protectionValue.leadingAnchor.constraint(equalTo: protectionCaption.leadingAnchor),
            protectionValue.trailingAnchor.constraint(equalTo: protectionCaption.trailingAnchor),

            autoSwitchLabel.topAnchor.constraint(equalTo: dashboardView.bottomAnchor, constant: 26),
            autoSwitchLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            autoSwitchLabel.widthAnchor.constraint(equalToConstant: 190),

            popup.centerYAnchor.constraint(equalTo: autoSwitchLabel.centerYAnchor),
            popup.leadingAnchor.constraint(equalTo: autoSwitchLabel.trailingAnchor, constant: 16),
            popup.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            rotationSelection.topAnchor.constraint(equalTo: autoSwitchLabel.bottomAnchor, constant: 20),
            rotationSelection.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            rotationSelection.trailingAnchor.constraint(lessThanOrEqualTo: contentView.trailingAnchor, constant: -34),
            launchButton.topAnchor.constraint(equalTo: rotationSelection.bottomAnchor, constant: 22),
            launchButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            launchButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34),

            sleepButton.topAnchor.constraint(equalTo: launchButton.bottomAnchor, constant: 16),
            sleepButton.leadingAnchor.constraint(equalTo: launchButton.leadingAnchor),
            sleepButton.trailingAnchor.constraint(equalTo: launchButton.trailingAnchor),

            restartButton.topAnchor.constraint(equalTo: sleepButton.bottomAnchor, constant: 16),
            restartButton.leadingAnchor.constraint(equalTo: sleepButton.leadingAnchor),
            restartButton.trailingAnchor.constraint(equalTo: sleepButton.trailingAnchor),

            dailyButton.topAnchor.constraint(equalTo: restartButton.bottomAnchor, constant: 16),
            dailyButton.leadingAnchor.constraint(equalTo: restartButton.leadingAnchor),
            dailyButton.widthAnchor.constraint(equalToConstant: 178),

            dailyPicker.centerYAnchor.constraint(equalTo: dailyButton.centerYAnchor),
            dailyPicker.leadingAnchor.constraint(equalTo: dailyButton.trailingAnchor, constant: 12),
            dailyPicker.widthAnchor.constraint(equalToConstant: 112),

            healthLogButton.topAnchor.constraint(equalTo: dailyButton.bottomAnchor, constant: 26),
            healthLogButton.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            healthLogButton.widthAnchor.constraint(equalToConstant: 190),

            noteLabel.topAnchor.constraint(equalTo: healthLogButton.bottomAnchor, constant: 22),
            noteLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 34),
            noteLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -34)
        ])

        settingsWindow = panel
        updateSettingsControls()
        startDashboardTimer()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func rotationChannelChanged(_ sender: NSButton) {
        let selected = Channel.allCases.filter { rotationChannelButtons[$0]?.state == .on }
        UserDefaults.standard.set(selected.map(\.rawValue), forKey: ChannelRotation.preferenceKey)
        StreamHealthLog.append("Rotation channels: " + (selected.isEmpty ? "off" : selected.map(\.title).joined(separator: ", ")))
        restartRotationTimer()
        refreshDashboard()
    }

    @objc private func rotationPopupChanged(_ sender: NSPopUpButton) {
        guard let seconds = sender.selectedItem?.representedObject as? Int else { return }
        UserDefaults.standard.set(seconds, forKey: Self.rotationPreferenceKey)
        StreamHealthLog.append("Auto-switch interval changed to \(sender.titleOfSelectedItem ?? "\(seconds) seconds")")
        restartRotationTimer()
    }

    @objc private func launchAtLoginChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: Self.launchAtLoginPreferenceKey)
        applyLaunchAtLoginPreference(reportErrors: true)
        updateSettingsControls()
    }

    @objc private func disableSleepChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: Self.disableSleepPreferenceKey)
        StreamHealthLog.append("Disable sleep while streaming \(enabled ? "enabled" : "disabled")")
        applySleepPreference()
        updateSettingsControls()
    }

    @objc private func restartOnUnhealthyChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: Self.restartOnUnhealthyPreferenceKey)
        StreamHealthLog.append("Restart on unhealthy stream \(enabled ? "enabled" : "disabled")")
        if enabled {
            startHealthRestartTimer()
        } else {
            unhealthySince = nil
        }
        updateSettingsControls()
    }

    @objc private func dailyRestartChanged(_ sender: NSButton) {
        let enabled = sender.state == .on
        UserDefaults.standard.set(enabled, forKey: Self.dailyRestartPreferenceKey)
        StreamHealthLog.append("Daily auto-restart \(enabled ? "enabled" : "disabled")")
        scheduleDailyRestart()
        updateSettingsControls()
    }

    @objc private func dailyRestartTimeChanged(_ sender: NSDatePicker) {
        let components = Calendar.current.dateComponents([.hour, .minute], from: sender.dateValue)
        let minuteOfDay = (components.hour ?? 0) * 60 + (components.minute ?? 0)
        UserDefaults.standard.set(minuteOfDay, forKey: Self.dailyRestartMinutePreferenceKey)
        StreamHealthLog.append("Daily auto-restart time changed to \(formatRestartTime(minuteOfDay: minuteOfDay))")
        scheduleDailyRestart()
        updateSettingsControls()
    }

    @objc private func showHealthLogWindow() {
        if let healthLogWindow {
            refreshHealthLogWindow()
            healthLogWindow.center()
            healthLogWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 520),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        panel.title = "Stream Health Log"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        panel.minSize = NSSize(width: 620, height: 380)

        let contentView = NSView()
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        panel.contentView = contentView

        let titleLabel = NSTextField(labelWithString: "Stream Health Log")
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        contentView.addSubview(titleLabel)

        let pathLabel = NSTextField(labelWithString: StreamHealthLog.logURL.path)
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingMiddle
        contentView.addSubview(pathLabel)

        let refreshButton = NSButton(title: "Refresh", target: self, action: #selector(refreshHealthLogWindow))
        refreshButton.translatesAutoresizingMaskIntoConstraints = false
        refreshButton.bezelStyle = .rounded
        contentView.addSubview(refreshButton)

        let clearButton = NSButton(title: "Clear", target: self, action: #selector(clearHealthLog))
        clearButton.translatesAutoresizingMaskIntoConstraints = false
        clearButton.bezelStyle = .rounded
        contentView.addSubview(clearButton)

        let scrollView = NSScrollView()
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.borderType = .bezelBorder
        contentView.addSubview(scrollView)

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        textView.textColor = .labelColor
        textView.backgroundColor = .textBackgroundColor
        textView.isHorizontallyResizable = true
        textView.isVerticallyResizable = true
        textView.autoresizingMask = [.width]
        scrollView.documentView = textView
        healthLogTextView = textView

        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 22),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            titleLabel.trailingAnchor.constraint(lessThanOrEqualTo: refreshButton.leadingAnchor, constant: -16),

            refreshButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            refreshButton.trailingAnchor.constraint(equalTo: clearButton.leadingAnchor, constant: -10),
            refreshButton.widthAnchor.constraint(equalToConstant: 92),

            clearButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            clearButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            clearButton.widthAnchor.constraint(equalToConstant: 82),

            pathLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 6),
            pathLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            pathLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: pathLabel.bottomAnchor, constant: 16),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -24),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -24)
        ])

        healthLogWindow = panel
        refreshHealthLogWindow()
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func refreshHealthLogWindow() {
        healthLogTextView?.string = StreamHealthLog.read()
        if let textView = healthLogTextView {
            textView.scrollRangeToVisible(NSRange(location: textView.string.count, length: 0))
        }
    }

    @objc private func clearHealthLog() {
        StreamHealthLog.clear()
        refreshHealthLogWindow()
    }

    private func select(_ channel: Channel, userInitiated: Bool) {
        guard channel != currentChannel else {
            StreamHealthLog.append("Reloading current channel: \(channel.title)")
            if userInitiated {
                failedChannelCooldowns.removeValue(forKey: channel)
            }
            playerViewController.recoverNow(reason: "Reload current channel")
            if userInitiated {
                restartRotationTimer()
            }
            refreshDashboard()
            return
        }

        if userInitiated {
            failedChannelCooldowns.removeValue(forKey: channel)
        }
        StreamHealthLog.append("\(userInitiated ? "Manual" : "Automatic") channel switch: \(currentChannel.title) to \(channel.title)")
        currentChannel = channel
        updateMenuState()
        refreshDashboard()
        playerViewController.load(channel)

        if userInitiated {
            restartRotationTimer()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender === window else { return true }
        StreamHealthLog.append("Player window closed: stopping stream")
        prepareForDesktopExit()
        isPlayerStoppedByClose = true
        isClosingPlayerWindow = true

        if sender.styleMask.contains(.fullScreen) {
            sender.toggleFullScreen(nil)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard self?.isClosingPlayerWindow == true else { return }
                self?.finishClosingPlayerWindow()
            }
        } else {
            finishClosingPlayerWindow()
        }
        return false
    }

    private func buildWindow() {
        let frame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .resizable, .miniaturizable, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "CP24 HLS Kiosk"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary, .managed, .moveToActiveSpace]
        window.delegate = self
        window.isMovableByWindowBackground = true
        window.contentViewController = playerViewController
        window.minSize = NSSize(width: 960, height: 540)
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
    }

    private func buildMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        let about = NSMenuItem(title: "About CP24 HLS Kiosk", action: #selector(showAboutWindow), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)
        appMenu.addItem(.separator())
        let settings = NSMenuItem(title: "Settings...", action: #selector(showSettingsWindow), keyEquivalent: ",")
        settings.target = self
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        appMenu.addItem(NSMenuItem(title: "Quit CP24 HLS Kiosk", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        let channelsMenuItem = NSMenuItem()
        let channelsMenu = NSMenu(title: "Channels")

        let cp24 = NSMenuItem(title: "CP24", action: #selector(selectCP24), keyEquivalent: "1")
        cp24.keyEquivalentModifierMask = []
        cp24.target = self
        channelsMenu.addItem(cp24)
        channelMenuItems[.cp24] = cp24

        let citynews = NSMenuItem(title: "CityNews", action: #selector(selectCitynews), keyEquivalent: "2")
        citynews.keyEquivalentModifierMask = []
        citynews.target = self
        channelsMenu.addItem(citynews)
        channelMenuItems[.citynews] = citynews

        let global = NSMenuItem(title: "Global News Toronto", action: #selector(selectGlobalToronto), keyEquivalent: "3")
        global.keyEquivalentModifierMask = []
        global.target = self
        channelsMenu.addItem(global)
        channelMenuItems[.globalToronto] = global

        channelsMenu.addItem(.separator())
        let recover = NSMenuItem(title: "Reload Stream", action: #selector(recoverStream), keyEquivalent: "r")
        recover.keyEquivalentModifierMask = [.command]
        recover.target = self
        channelsMenu.addItem(recover)

        channelsMenuItem.submenu = channelsMenu
        mainMenu.addItem(channelsMenuItem)

        let dashboardMenuItem = NSMenuItem()
        let dashboardMenu = NSMenu(title: "Dashboard")
        let showDashboard = NSMenuItem(title: "Show Live Dashboard", action: #selector(showDashboardWindow), keyEquivalent: "d")
        showDashboard.keyEquivalentModifierMask = [.command]
        showDashboard.target = self
        dashboardMenu.addItem(showDashboard)
        dashboardMenuItem.submenu = dashboardMenu
        mainMenu.addItem(dashboardMenuItem)

        let safeguardsMenuItem = NSMenuItem()
        let safeguardsMenu = NSMenu(title: "Safeguards")
        let showSafeguards = NSMenuItem(title: "Show Safeguards", action: #selector(showSafeguardsWindow), keyEquivalent: "")
        showSafeguards.target = self
        safeguardsMenu.addItem(showSafeguards)
        safeguardsMenuItem.submenu = safeguardsMenu
        mainMenu.addItem(safeguardsMenuItem)

        NSApp.mainMenu = mainMenu
        updateMenuState()
    }

    private func updateMenuState() {
        for (channel, item) in channelMenuItems {
            item.state = channel == currentChannel ? .on : .off
        }
    }

    private func installKeyboardShortcuts() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard
                let self,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                let characters = event.charactersIgnoringModifiers
            else {
                return event
            }

            switch characters {
            case "1":
                self.select(.cp24, userInitiated: true)
                return nil
            case "2":
                self.select(.citynews, userInitiated: true)
                return nil
            case "3":
                self.select(.globalToronto, userInitiated: true)
                return nil
            case "\u{1B}":
                self.shrinkPlayerWindow()
                return nil
            default:
                return event
            }
        }
    }

    private func restartRotationTimer() {
        rotationTimer?.invalidate()
        rotationTimer = nil
        guard !ChannelRotation.included(in: .standard).isEmpty else { return }
        let interval = TimeInterval(selectedRotationSeconds())
        rotationTimer = Timer.scheduledTimer(timeInterval: interval, target: self, selector: #selector(rotateChannel), userInfo: nil, repeats: true)
        rotationTimer?.tolerance = min(60, interval * 0.1)
    }

    private func startDashboardTimer() {
        dashboardTimer?.invalidate()
        dashboardTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshDashboard()
            }
        }
        dashboardTimer?.tolerance = 1
    }

    private func selectedRotationSeconds() -> Int {
        let savedSeconds = UserDefaults.standard.integer(forKey: Self.rotationPreferenceKey)
        let validSeconds = Set(Self.rotationOptions.map(\.seconds))
        if validSeconds.contains(savedSeconds) {
            return savedSeconds
        }
        return Self.defaultRotationSeconds
    }

    private func nextAutomaticChannel() -> Channel? {
        clearExpiredChannelCooldowns()
        return ChannelRotation.next(after: currentChannel,
            included: ChannelRotation.included(in: .standard),
            unavailable: Set(failedChannelCooldowns.keys))
    }

    private func rotationDashboardText() -> String {
        let included = ChannelRotation.included(in: .standard)
        if included.isEmpty { return "Off" }
        if included.count == 1 { return "One channel" }

        let seconds = selectedRotationSeconds()
        if let option = Self.rotationOptions.first(where: { $0.seconds == seconds }) {
            return option.title
        }
        return "\(seconds / 60) min"
    }

    private func updateSettingsControls() {
        let included = ChannelRotation.included(in: .standard)
        for (channel, button) in rotationChannelButtons {
            button.state = included.contains(channel) ? .on : .off
        }
        let currentSeconds = selectedRotationSeconds()
        if let popup = rotationPopupButton {
            for item in popup.itemArray {
                if item.representedObject as? Int == currentSeconds {
                    popup.select(item)
                    break
                }
            }
        }

        launchAtLoginButton?.state = LoginItemManager.isEnabled ? .on : .off
        disableSleepButton?.state = UserDefaults.standard.bool(forKey: Self.disableSleepPreferenceKey) ? .on : .off
        restartOnUnhealthyButton?.state = UserDefaults.standard.bool(forKey: Self.restartOnUnhealthyPreferenceKey) ? .on : .off
        dailyRestartButton?.state = UserDefaults.standard.bool(forKey: Self.dailyRestartPreferenceKey) ? .on : .off
        dailyRestartPicker?.dateValue = dateForRestartMinute(selectedDailyRestartMinute())
        dailyRestartPicker?.isEnabled = UserDefaults.standard.bool(forKey: Self.dailyRestartPreferenceKey)
        refreshDashboard()
    }

    private func applyLaunchAtLoginPreference(reportErrors: Bool) {
        let enabled = UserDefaults.standard.bool(forKey: Self.launchAtLoginPreferenceKey)
        do {
            try LoginItemManager.setEnabled(enabled)
            StreamHealthLog.append("Launch at login \(enabled ? "enabled" : "disabled")")
        } catch {
            StreamHealthLog.append("Launch at login failed: \(error.localizedDescription)")
            if reportErrors {
                UserDefaults.standard.set(false, forKey: Self.launchAtLoginPreferenceKey)
                showAlert(
                    title: "Launch at Login",
                    message: "macOS could not update Launch at Login for this copy of CP24 HLS Kiosk. Move the app to Applications, open it again, then turn this setting on."
                )
            }
        }
    }

    private func applySleepPreference() {
        let shouldDisableSleep = UserDefaults.standard.bool(forKey: Self.disableSleepPreferenceKey) && !isPlayerStoppedByClose
        PowerManager.shared.setSleepDisabled(shouldDisableSleep)
    }

    private func handlePlayerHealth(isHealthy: Bool, reason: String) {
        if isHealthy {
            lastHealthyAt = Date()
            lastKnownGoodChannel = currentChannel
            failedChannelCooldowns.removeValue(forKey: currentChannel)
            unhealthySince = nil
        } else if unhealthySince == nil {
            unhealthySince = Date()
            StreamHealthLog.append("Stream marked unhealthy: \(reason)")
        }
        refreshDashboard()
    }

    private func handleNetworkStatus(isOnline: Bool, detail: String) {
        guard isNetworkOnline != isOnline || networkStatusText != detail else { return }
        isNetworkOnline = isOnline
        networkStatusText = detail
        if isOnline {
            StreamHealthLog.append("Network available: \(detail)")
            playerViewController.showNetworkWaiting(false)
            if !isPlayerStoppedByClose {
                playerViewController.recoverNow(reason: "Network restored")
            }
        } else {
            StreamHealthLog.append("Network unavailable: \(detail)")
            unhealthySince = nil
            playerViewController.showNetworkWaiting(true)
        }
        refreshDashboard()
    }

    private func markChannelUnavailable(_ channel: Channel) {
        let until = Date().addingTimeInterval(Self.failedChannelCooldownSeconds)
        failedChannelCooldowns[channel] = until
        StreamHealthLog.append("\(channel.title) held from auto-rotation until \(formatRestartDate(until))")
        refreshDashboard()
    }

    private func isChannelTemporarilyUnavailable(_ channel: Channel) -> Bool {
        clearExpiredChannelCooldowns()
        guard let until = failedChannelCooldowns[channel] else { return false }
        return until > Date()
    }

    private func clearExpiredChannelCooldowns() {
        let now = Date()
        failedChannelCooldowns = failedChannelCooldowns.filter { $0.value > now }
    }

    private func refreshDashboard() {
        clearExpiredChannelCooldowns()
        let currentChannelText = currentChannel.title
        let lastGoodText = lastKnownGoodChannel.title
        let lastHealthyText = timeAgo(from: lastHealthyAt)
        let nextRestartText = nextRestartDashboardText()
        let protectionText = protectionDashboardText()
        let rotationText = rotationDashboardText()
        let systemSnapshot = SystemMonitor.snapshot(logURL: StreamHealthLog.logURL)

        dashboardChannelLabel?.stringValue = currentChannelText
        dashboardNetworkLabel?.stringValue = networkStatusText
        dashboardLastGoodLabel?.stringValue = lastGoodText
        dashboardLastHealthyLabel?.stringValue = lastHealthyText
        dashboardNextRestartLabel?.stringValue = nextRestartText
        dashboardProtectionLabel?.stringValue = protectionText

        menuDashboardChannelLabel?.stringValue = currentChannelText
        menuDashboardNetworkLabel?.stringValue = networkStatusText
        menuDashboardLastGoodLabel?.stringValue = lastGoodText
        menuDashboardLastHealthyLabel?.stringValue = lastHealthyText
        menuDashboardNextRestartLabel?.stringValue = nextRestartText
        menuDashboardProtectionLabel?.stringValue = protectionText

        dashboardMemoryLabel?.stringValue = systemSnapshot.memoryText
        dashboardDiskLabel?.stringValue = systemSnapshot.diskText
        dashboardNetworkActivityLabel?.stringValue = systemSnapshot.networkActivityText
        dashboardAppMemoryLabel?.stringValue = systemSnapshot.appMemoryText
        dashboardCpuLabel?.stringValue = systemSnapshot.cpuLoadText
        dashboardUptimeLabel?.stringValue = systemSnapshot.uptimeText
        dashboardLogSizeLabel?.stringValue = systemSnapshot.logSizeText
        dashboardAutoRotationLabel?.stringValue = rotationText

        memoryGraphView?.addSample(systemSnapshot.memoryUsedRatio)
        diskGraphView?.addSample(systemSnapshot.diskUsedRatio)
        networkGraphView?.addSample(systemSnapshot.networkActivityRatio)
        appMemoryGraphView?.addSample(systemSnapshot.appMemoryRatio)
        cpuGraphView?.addSample(systemSnapshot.cpuLoadRatio)
    }

    private func startHealthRestartTimer() {
        healthRestartTimer?.invalidate()
        healthRestartTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkSustainedUnhealthyStream()
            }
        }
        healthRestartTimer?.tolerance = 10
    }

    private func checkSustainedUnhealthyStream() {
        guard
            UserDefaults.standard.bool(forKey: Self.restartOnUnhealthyPreferenceKey),
            isNetworkOnline,
            !isPlayerStoppedByClose,
            let unhealthySince
        else {
            return
        }

        if Date().timeIntervalSince(unhealthySince) >= Self.unhealthyRestartSeconds {
            relaunchApp(reason: "Stream unhealthy for 10 minutes")
        }
    }

    private func scheduleDailyRestart() {
        dailyRestartTimer?.invalidate()
        guard UserDefaults.standard.bool(forKey: Self.dailyRestartPreferenceKey) else {
            dailyRestartTimer = nil
            return
        }

        let restartDate = nextDailyRestartDate()
        dailyRestartTimer = Timer(fireAt: restartDate, interval: 0, target: self, selector: #selector(performDailyRestart), userInfo: nil, repeats: false)
        if let dailyRestartTimer {
            dailyRestartTimer.tolerance = 60
            RunLoop.main.add(dailyRestartTimer, forMode: .common)
        }
        StreamHealthLog.append("Daily auto-restart scheduled for \(formatRestartDate(restartDate))")
    }

    @objc private func performDailyRestart() {
        relaunchApp(reason: "Daily auto-restart at \(formatRestartTime(minuteOfDay: selectedDailyRestartMinute()))")
    }

    private func relaunchApp(reason: String) {
        StreamHealthLog.append("Relaunch requested: \(reason)")
        PowerManager.shared.setSleepDisabled(false)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            Self.delayedRelaunchScript,
            "news-tv-kiosk-relauncher",
            Bundle.main.bundleURL.path,
            StreamHealthLog.logURL.path,
            reason
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            NSApp.terminate(nil)
        } catch {
            StreamHealthLog.append("Relaunch helper failed: \(error.localizedDescription)")
        }
    }

    private static let delayedRelaunchScript = #"""
app_bundle="$1"
log_file="$2"
reason="$3"

log_event() {
  mkdir -p "$(dirname "$log_file")"
  printf "%s  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log_file"
}

log_event "Delayed relaunch helper started: $reason"
sleep 2
/usr/bin/open -n "$app_bundle"
status="$?"
if [ "$status" -eq 0 ]; then
  log_event "Delayed relaunch helper opened app"
else
  log_event "Delayed relaunch helper failed with status $status"
fi
"""#

    private func selectedDailyRestartMinute() -> Int {
        let storedMinute = UserDefaults.standard.integer(forKey: Self.dailyRestartMinutePreferenceKey)
        if (0..<(24 * 60)).contains(storedMinute) {
            return storedMinute
        }
        return Self.defaultDailyRestartMinute
    }

    private func dateForRestartMinute(_ minuteOfDay: Int) -> Date {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay) ?? Date()
    }

    private func nextDailyRestartDate() -> Date {
        let calendar = Calendar.current
        let now = Date()
        let candidate = dateForRestartMinute(selectedDailyRestartMinute())
        if candidate > now {
            return candidate
        }
        return calendar.date(byAdding: .day, value: 1, to: candidate) ?? now.addingTimeInterval(24 * 60 * 60)
    }

    private func formatRestartTime(minuteOfDay: Int) -> String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter.string(from: dateForRestartMinute(minuteOfDay))
    }

    private func formatRestartDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeAgo(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 5 {
            return "Now"
        }
        if seconds < 60 {
            return "\(seconds)s ago"
        }
        let minutes = seconds / 60
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = minutes / 60
        if hours < 24 {
            return "\(hours)h ago"
        }
        return "\(hours / 24)d ago"
    }

    private func nextRestartDashboardText() -> String {
        if UserDefaults.standard.bool(forKey: Self.dailyRestartPreferenceKey) {
            return formatRestartDate(nextDailyRestartDate())
        }
        return "Daily off"
    }

    private func protectionDashboardText() -> String {
        clearExpiredChannelCooldowns()
        if !isNetworkOnline {
            return "Waiting for network"
        }
        let blockedChannels = failedChannelCooldowns.keys.map(\.title).sorted()
        if !blockedChannels.isEmpty {
            return "Holding \(blockedChannels.joined(separator: ", "))"
        }
        if UserDefaults.standard.bool(forKey: Self.restartOnUnhealthyPreferenceKey) {
            return "Guarded"
        }
        return "Basic"
    }

    private func showAlert(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func enterFullScreen() {
        guard let window else { return }
        if !window.styleMask.contains(.fullScreen) {
            window.collectionBehavior = [.fullScreenPrimary, .managed, .moveToActiveSpace]
            applyFullScreenWindowStyle()
            applyKioskPresentation()
            window.toggleFullScreen(nil)
        }
    }

    private func shrinkPlayerWindow() {
        guard let window else { return }
        shouldCenterAfterLeavingFullScreen = true
        applyWindowedPresentation()

        if window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
            centerWindowedPlayerAfterDelay(0.05)
            centerWindowedPlayerAfterDelay(0.20)
            centerWindowedPlayerAfterDelay(0.45)
        } else {
            centerWindowedPlayer()
        }
    }

    private func restorePlayerWindow() {
        guard let window else { return }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        if isPlayerStoppedByClose {
            isPlayerStoppedByClose = false
            lastHealthyAt = Date()
            unhealthySince = nil
            StreamHealthLog.append("Dock reopen: starting \(currentChannel.title)")
            applySleepPreference()
            playerViewController.load(currentChannel, reason: "Starting \(currentChannel.title)")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            self?.enterFullScreen()
        }
    }

    func windowDidEnterFullScreen(_ notification: Notification) {
        applyFullScreenWindowStyle()
        applyKioskPresentation()
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        applyWindowedPresentation()
        if shouldCenterAfterLeavingFullScreen {
            centerWindowedPlayer()
        }
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        applyWindowedPresentation()
        if isTerminatingAfterFullScreenExit {
            finishTerminatingAfterFullScreenExit()
            return
        }

        if isClosingPlayerWindow {
            finishClosingPlayerWindow()
            return
        }

        if shouldCenterAfterLeavingFullScreen {
            centerWindowedPlayer()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.centerWindowedPlayer()
            }
            shouldCenterAfterLeavingFullScreen = false
        }
    }

    private func finishClosingPlayerWindow() {
        guard let window else { return }
        if window.styleMask.contains(.fullScreen) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                guard self?.isClosingPlayerWindow == true else { return }
                self?.finishClosingPlayerWindow()
            }
            return
        }

        isClosingPlayerWindow = false
        shouldCenterAfterLeavingFullScreen = false
        applyWindowedPresentation()
        applyWindowedWindowStyle()
        window.collectionBehavior = [.managed, .moveToActiveSpace]
        window.orderOut(nil)
        activateAppMenuAfterClose()
    }

    private func finishTerminatingAfterFullScreenExit() {
        guard isTerminatingAfterFullScreenExit else { return }
        applyWindowedPresentation()
        if let window {
            applyWindowedWindowStyle()
            window.collectionBehavior = [.managed, .moveToActiveSpace]
            window.orderOut(nil)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            NSApp.terminate(nil)
        }
    }

    private func prepareForDesktopExit() {
        playerViewController.stopPlayback()
        PowerManager.shared.setSleepDisabled(false)
        unhealthySince = nil
        applyWindowedPresentation()
    }

    private func activateAppMenuAfterClose() {
        NSApp.activate(ignoringOtherApps: true)
        StreamHealthLog.append("Player window hidden: app menu remains active")
    }

    private func centerWindowedPlayerAfterDelay(_ delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard self?.shouldCenterAfterLeavingFullScreen == true else { return }
            self?.centerWindowedPlayer()
        }
    }

    private func centerWindowedPlayer() {
        guard let window else { return }
        applyWindowedWindowStyle()

        let screenFrame = (window.screen ?? NSScreen.main)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1280, height: 720)
        let maxWidth = screenFrame.width * 0.72
        let maxHeight = screenFrame.height * 0.72
        var width = min(maxWidth, maxHeight * Self.windowedAspectRatio)
        var height = width / Self.windowedAspectRatio

        if height > maxHeight {
            height = maxHeight
            width = height * Self.windowedAspectRatio
        }

        width = max(width, 960)
        height = max(height, 540)

        let origin = NSPoint(
            x: screenFrame.midX - width / 2,
            y: screenFrame.midY - height / 2
        )
        window.setFrame(NSRect(origin: origin, size: NSSize(width: width, height: height)), display: true, animate: false)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func applyFullScreenWindowStyle() {
        guard let window else { return }
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
    }

    private func applyWindowedWindowStyle() {
        guard let window else { return }
        window.titleVisibility = .visible
        window.titlebarAppearsTransparent = false
        window.styleMask.insert(.titled)
        window.styleMask.insert(.resizable)
        window.styleMask.insert(.miniaturizable)
        window.styleMask.insert(.closable)
        window.isMovableByWindowBackground = true
    }

    private func applyKioskPresentation() {
        NSApp.presentationOptions = [
            .autoHideDock,
            .autoHideMenuBar,
            .disableHideApplication,
            .disableProcessSwitching
        ]
    }

    private func applyWindowedPresentation() {
        NSApp.presentationOptions = []
    }
}
