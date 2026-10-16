import Foundation
@main struct ChannelRotationTests {
 static func main() {
  let suite = "CP24RotationTests-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  precondition(ChannelRotation.included(in: defaults) == Set(Channel.allCases))
  defaults.set([], forKey: ChannelRotation.preferenceKey)
  precondition(ChannelRotation.included(in: defaults).isEmpty)
  defaults.set(["cp24", "globalToronto", "obsolete"], forKey: ChannelRotation.preferenceKey)
  precondition(ChannelRotation.included(in: UserDefaults(suiteName: suite)!) == [.cp24, .globalToronto])
  var checks = 0
  let all = Channel.allCases
  for includedMask in 0..<8 {
   for blockedMask in 0..<8 {
    let included = Set(all.enumerated().filter { includedMask & (1 << $0.offset) != 0 }.map(\.element))
    let blocked = Set(all.enumerated().filter { blockedMask & (1 << $0.offset) != 0 }.map(\.element))
    for current in all {
     let result = ChannelRotation.next(after: current, included: included, unavailable: blocked)
     let candidates = included.subtracting(blocked).subtracting([current])
     precondition((result == nil) == candidates.isEmpty)
     if let result { precondition(candidates.contains(result)) }
     checks += 1
    }
   }
  }
  precondition(ChannelRotation.next(after: .cp24, included: Set(all), unavailable: []) == .citynews)
  precondition(ChannelRotation.next(after: .citynews, included: Set(all), unavailable: []) == .globalToronto)
  precondition(ChannelRotation.next(after: .globalToronto, included: Set(all), unavailable: []) == .cp24)
  precondition(ChannelRotation.next(after: .cp24, included: Set(all), unavailable: [.citynews]) == .globalToronto)
  print("Passed \(checks) selection combinations plus preference persistence and cycle-order tests")
 }
}
