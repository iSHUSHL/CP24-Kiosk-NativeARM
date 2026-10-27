import Foundation

/// Quick recovery after playback has started, with a longer first-load grace period.
enum PlaybackRecoveryPolicy {
    static let frozenPlaybackSeconds: TimeInterval = 15
    static let startupGraceSeconds: TimeInterval = 45

    static func reason(secondsWithoutProgress: TimeInterval, secondsSinceLoad: TimeInterval,
                       hasPlayed: Bool, buffering: Bool) -> String? {
        guard secondsWithoutProgress >= frozenPlaybackSeconds else { return nil }
        guard hasPlayed || secondsSinceLoad >= startupGraceSeconds else { return nil }
        return buffering ? "Buffering without playback progress" : "Playback stopped progressing"
    }
}
