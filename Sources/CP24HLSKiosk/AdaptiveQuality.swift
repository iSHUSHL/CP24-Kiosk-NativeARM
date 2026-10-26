import Foundation

/// Extra headroom on top of AVPlayer's HLS adaptation. Values are preferred caps,
/// not fixed rendition requests: the broadcaster must offer lower quality variants.
struct AdaptiveQuality {
    static let caps: [Double] = [800_000, 1_500_000, 2_500_000, 4_000_000, 8_000_000]
    private(set) var level = 2
    private var lastReduction = Date.distantPast
    private var stableSince: Date?
    var peakBitRate: Double { Self.caps[level] }
    var forwardBuffer: TimeInterval { level <= 1 ? 30 : 20 }

    mutating func interruptStability() { stableSince = nil }

    mutating func reduce(at now: Date) -> Bool {
        stableSince = nil
        guard level > 0, now.timeIntervalSince(lastReduction) >= 20 else { return false }
        level -= 1
        lastReduction = now
        return true
    }

    mutating func sample(at now: Date, progressing: Bool, buffering: Bool,
                         bufferSeconds: Double, throughput: Double?) -> Bool {
        if buffering { return reduce(at: now) }
        if let throughput, throughput.isFinite, throughput > 0,
           throughput * 0.65 < peakBitRate, bufferSeconds < 8 {
            return reduce(at: now)
        }
        guard progressing, bufferSeconds >= 12 else {
            stableSince = nil
            return false
        }
        if stableSince == nil { stableSince = now }
        guard let stableSince, now.timeIntervalSince(stableSince) >= 120,
              level + 1 < Self.caps.count,
              let throughput, throughput.isFinite,
              throughput * 0.65 >= Self.caps[level + 1] else { return false }
        level += 1
        self.stableSince = now
        return true
    }
}
