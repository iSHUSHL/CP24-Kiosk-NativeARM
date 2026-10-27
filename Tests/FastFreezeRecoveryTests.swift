import AppKit
import AVFoundation
@main struct FastFreezeRecoveryTests {
 @MainActor static func main() async {
  _ = NSApplication.shared
  let controller = PlayerViewController()
  controller.initialChannel = .citynews
  _ = controller.view
  let player = Mirror(reflecting: controller).children.first { $0.label == "player" }!.value as! AVPlayer
  player.isMuted = true
  try? await Task.sleep(nanoseconds: 12_000_000_000)
  precondition(player.currentTime().seconds.isFinite && player.rate > 0, "Live playback must start before freeze injection")
  let original = player.currentItem!
  player.pause() // Simulates a stopped playhead without an error/end notification.
  let start = Date()
  for _ in 0..<30 {
   try? await Task.sleep(nanoseconds: 1_000_000_000)
   if player.currentItem !== original { break }
  }
  let elapsed = Date().timeIntervalSince(start)
  precondition(player.currentItem !== original, "Silent stop must reload promptly")
  precondition(elapsed < 30)
  print("Simulated silent stop reloaded in \(String(format: "%.1f", elapsed)) seconds")
  controller.stopPlayback()
 }
}
