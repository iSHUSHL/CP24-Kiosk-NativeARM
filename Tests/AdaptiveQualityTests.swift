import Foundation
@main struct AdaptiveQualityTests {
 static func main() {
  let t = Date(timeIntervalSince1970: 1000)
  var q = AdaptiveQuality()
  precondition(q.peakBitRate == 2_500_000)
  precondition(q.reduce(at: t) && q.peakBitRate == 1_500_000)
  precondition(!q.reduce(at: t.addingTimeInterval(1)))
  precondition(q.reduce(at: t.addingTimeInterval(20)) && q.peakBitRate == 800_000)
  precondition(!q.reduce(at: t.addingTimeInterval(40)))
  precondition(q.forwardBuffer == 30)
  // No upgrade without sustained stability, fresh throughput, and sufficient buffer.
  for n in 0..<120 {
   precondition(!q.sample(at: t.addingTimeInterval(50 + Double(n)), progressing: true,
      buffering: false, bufferSeconds: 15, throughput: 20_000_000))
  }
  precondition(!q.sample(at: t.addingTimeInterval(170), progressing: true,
      buffering: false, bufferSeconds: 15, throughput: nil))
  precondition(q.sample(at: t.addingTimeInterval(175), progressing: true,
      buffering: false, bufferSeconds: 15, throughput: 20_000_000))
  precondition(q.peakBitRate == 1_500_000)
  q.interruptStability()
  precondition(!q.sample(at: t.addingTimeInterval(500), progressing: true,
      buffering: false, bufferSeconds: 15, throughput: 20_000_000))
  precondition(q.sample(at: t.addingTimeInterval(510), progressing: true,
      buffering: false, bufferSeconds: 3, throughput: 900_000))
  // Invalid bandwidth values cannot trigger upgrades.
  for throughput in [Double.nan, Double.infinity, -1, 0] {
   precondition(!q.sample(at: t.addingTimeInterval(1000), progressing: true,
      buffering: false, bufferSeconds: 15, throughput: throughput))
  }
  var channels: [Channel: AdaptiveQuality] = [.cp24: q, .citynews: AdaptiveQuality()]
  precondition(channels[.cp24]!.peakBitRate == 800_000)
  precondition(channels[.citynews]!.peakBitRate == 2_500_000)
  channels[.cp24]?.interruptStability()
  precondition(channels[.cp24]!.peakBitRate == 800_000)
  print("Adaptive quality tests passed: downgrade, debounce, floor, cautious upgrade, buffer/throughput gates, invalid samples, and per-channel state")
 }
}
