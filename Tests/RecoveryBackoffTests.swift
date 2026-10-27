import AppKit
import AVFoundation
@main struct RecoveryBackoffTests {
 @MainActor static func main() async {
  _ = NSApplication.shared
  let controller = PlayerViewController()
  controller.initialChannel = .citynews
  _ = controller.view
  let player = Mirror(reflecting: controller).children.first { $0.label == "player" }!.value as! AVPlayer
  player.isMuted = true
  controller.recoverNow(reason: "Test immediate recovery")
  let item = player.currentItem!
  controller.recoverNow(reason: "Test failure during backoff")
  precondition(player.currentItem === item)
  precondition(controller.playbackDiagnostics.contains("Recovery queued"))
  try? await Task.sleep(nanoseconds: 11_000_000_000)
  precondition(player.currentItem !== item, "Queued recovery must execute without waiting for the health timeout")
  controller.recoverNow(reason: "Test cancellation")
  controller.stopPlayback()
  let optionalTimer = Mirror(reflecting: controller).children.first { $0.label == "pendingRecoveryTimer" }!.value
  precondition(Mirror(reflecting: optionalTimer).children.isEmpty, "Stop must remove the queued retry")
  precondition(player.currentItem == nil)
  print("Backoff requests were queued, retried on time, and canceled on stop")
 }
}
