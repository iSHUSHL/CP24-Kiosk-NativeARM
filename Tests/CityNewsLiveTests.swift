import AVFoundation
import AppKit
@main struct CityNewsLive {
 @MainActor static func main() async {
  setbuf(stdout,nil)
  _ = NSApplication.shared
  let controller = PlayerViewController()
  controller.initialChannel = .citynews
  _ = controller.view
  let player = Mirror(reflecting: controller).children.first { $0.label == "player" }!.value as! AVPlayer
  player.isMuted = true
  let original = player.currentItem!
  precondition((original.asset as! AVURLAsset).url.absoluteString.contains("/20002916/"))
  let video = AVPlayerItemVideoOutput(pixelBufferAttributes:nil)
  original.add(video)
  var frames=0
  for n in 1...120 {
   try? await Task.sleep(nanoseconds:1_000_000_000)
   if video.copyPixelBuffer(forItemTime:player.currentTime(),itemTimeForDisplay:nil) != nil { frames += 1 }
   if n % 30 == 0 {
    print("\(n)s: decoded=\(frames), time=\(player.currentTime().seconds), same item=\(player.currentItem === original), error=\(String(describing:original.error))")
   }
  }
  let liveSucceeded = frames > 100 && player.currentItem === original && original.error == nil
  print(controller.playbackDiagnostics)
  NotificationCenter.default.post(name:.AVPlayerItemDidPlayToEndTime,object:original)
  precondition(player.currentItem !== original,"End notification must trigger prompt recovery")
  let replacement=player.currentItem!
  NotificationCenter.default.post(name:.AVPlayerItemDidPlayToEndTime,object:original)
  precondition(player.currentItem === replacement,"Ignore a stale item's end notification")
  controller.stopPlayback()
  print("Live-end recovery and stale-notification filtering passed")
  precondition(liveSucceeded,"CityNews did not sustain live playback")
 }
}
