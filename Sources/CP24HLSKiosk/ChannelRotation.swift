import Foundation

/// Shared selection rules for automatic rotation and failure fallback.
enum ChannelRotation {
    static let preferenceKey = "RotationIncludedChannels"

    static func included(in defaults: UserDefaults) -> Set<Channel> {
        guard let values = defaults.stringArray(forKey: preferenceKey) else {
            return Set(Channel.allCases)
        }
        return Set(values.compactMap(Channel.init(rawValue:)))
    }

    static func next(after current: Channel, included: Set<Channel>, unavailable: Set<Channel>) -> Channel? {
        let channels = Channel.allCases
        guard let index = channels.firstIndex(of: current) else { return nil }
        for offset in 1..<channels.count {
            let candidate = channels[(index + offset) % channels.count]
            if included.contains(candidate) && !unavailable.contains(candidate) { return candidate }
        }
        return nil
    }
}
