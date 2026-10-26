import Foundation
@main struct StartupAndUpdatesTests {
 static func main() async throws {
  let suite = "CP24FeatureTests-" + UUID().uuidString
  let defaults = UserDefaults(suiteName: suite)!
  defer { defaults.removePersistentDomain(forName: suite) }
  precondition(StartupPreference.channel(in: defaults) == .cp24)
  defaults.set("globalToronto", forKey: StartupPreference.lastChannelKey)
  precondition(StartupPreference.channel(in: defaults) == .globalToronto)
  for channel in Channel.allCases {
   defaults.set(channel.rawValue, forKey: StartupPreference.choiceKey)
   precondition(StartupPreference.channel(in: defaults) == channel)
  }
  defaults.set(StartupPreference.lastWatched, forKey: StartupPreference.choiceKey)
  precondition(StartupPreference.channel(in: UserDefaults(suiteName: suite)!) == .globalToronto)
  defaults.set("removed-channel", forKey: StartupPreference.lastChannelKey)
  precondition(StartupPreference.channel(in: defaults) == .cp24)
  defaults.set("invalid", forKey: StartupPreference.choiceKey)
  precondition(StartupPreference.channel(in: defaults) == .cp24)

  precondition(AppVersion("2.10")! > AppVersion("2.9")!)
  precondition(AppVersion("v2.23")! == AppVersion("2.23.0")!)
  for tag in ["2.24-beta", "latest", "2..24", "", "2.4.", "9999999999999999999999999"] {
   precondition(AppVersion(tag) == nil)
  }
  func release(_ version: String, draft: Bool = false, prerelease: Bool = false,
               asset: String = "CP24-HLS-Kiosk-Notarized.dmg", state: String = "uploaded",
               url: String = "https://github.com/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/v2.24/CP24-HLS-Kiosk-Notarized.dmg") -> GitHubRelease {
   GitHubRelease(tag_name: version, draft: draft, prerelease: prerelease,
                 assets: [.init(name: asset, state: state, browser_download_url: URL(string: url)!)])
  }
  let releases = [release("v2.22"), release("v2.23"), release("v2.24"),
    release("v2.25", asset: "unsigned.zip"), release("v2.26", draft: true),
    release("v2.27", prerelease: true), release("latest"), release("v2.28", state: "new"),
    release("v2.29", url: "https://untrusted.example/Notarized.dmg")]
  precondition(UpdateChecker.newest(in: releases, newerThan: "2.23")?.version == "v2.24")
  precondition(UpdateChecker.newest(in: releases, newerThan: "2.24") == nil)
  precondition(UpdateChecker.newest(in: releases, newerThan: "bad") == nil)
  print("Startup selection, persistence, invalid preference fallback, numeric version ordering, and release/asset filtering passed")
  let live = try await UpdateChecker.fetch(newerThan: "2.23")
  print("Live GitHub API check passed; newer notarized update: \(live?.version ?? "none")")
 }
}
