import Foundation
@main struct PlaybackRecoveryPolicyTests {
 static func main() {
  for age in [20.0, 60, 600] {
   precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 14.9, secondsSinceLoad: age, hasPlayed: true, buffering: true) == nil)
   precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 15, secondsSinceLoad: age, hasPlayed: true, buffering: true) != nil)
   precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 15, secondsSinceLoad: age, hasPlayed: true, buffering: false) != nil)
  }
  precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 40, secondsSinceLoad: 40, hasPlayed: false, buffering: true) == nil)
  precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 45, secondsSinceLoad: 45, hasPlayed: false, buffering: true) != nil)
  precondition(PlaybackRecoveryPolicy.reason(secondsWithoutProgress: 0, secondsSinceLoad: 3600, hasPlayed: true, buffering: false) == nil)
  print("Fast recovery policy tests passed: 15-second freeze threshold, brief-buffer tolerance, and startup grace")
 }
}
