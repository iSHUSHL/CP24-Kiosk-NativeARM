import Foundation

enum StartupPreference {
    static let choiceKey = "StartupChannel"
    static let lastChannelKey = "LastWatchedChannel"
    static let lastWatched = "lastWatched"

    static func channel(in defaults: UserDefaults) -> Channel {
        let choice = defaults.string(forKey: choiceKey) ?? lastWatched
        if choice == lastWatched {
            return defaults.string(forKey: lastChannelKey).flatMap(Channel.init(rawValue:)) ?? .cp24
        }
        return Channel(rawValue: choice) ?? .cp24
    }
}
