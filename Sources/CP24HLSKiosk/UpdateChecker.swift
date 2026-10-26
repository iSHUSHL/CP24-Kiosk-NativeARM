import Foundation

struct AppVersion: Comparable {
    let parts: [Int]
    init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let components = value.split(separator: ".", omittingEmptySubsequences: false)
        guard !components.isEmpty, components.count <= 4,
              components.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }),
              components.allSatisfy({ Int($0) != nil }) else { return nil }
        parts = components.map { Int($0)! }
    }
    static func < (lhs: Self, rhs: Self) -> Bool {
        for i in 0..<max(lhs.parts.count, rhs.parts.count) {
            let a = i < lhs.parts.count ? lhs.parts[i] : 0
            let b = i < rhs.parts.count ? rhs.parts[i] : 0
            if a != b { return a < b }
        }
        return false
    }
    static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct GitHubRelease: Decodable {
    struct Asset: Decodable {
        let name: String
        let state: String
        let browser_download_url: URL
    }
    let tag_name: String
    let draft: Bool
    let prerelease: Bool
    let assets: [Asset]
}

struct AvailableUpdate {
    let version: String
    let downloadURL: URL
}

enum UpdateChecker {
    static let enabledKey = "AutomaticallyCheckForUpdates"
    static let lastCheckKey = "LastSuccessfulUpdateCheck"
    static func newest(in releases: [GitHubRelease], newerThan current: String) -> AvailableUpdate? {
        guard let current = AppVersion(current) else { return nil }
        return releases.compactMap { release -> (AppVersion, AvailableUpdate)? in
            guard !release.draft, !release.prerelease,
                  let version = AppVersion(release.tag_name), version > current,
                  let asset = release.assets.first(where: {
                      $0.state == "uploaded" && $0.name.lowercased().contains("notarized") &&
                      $0.name.lowercased().hasSuffix(".dmg") &&
                      $0.browser_download_url.scheme == "https" &&
                      $0.browser_download_url.host == "github.com" &&
                      $0.browser_download_url.path.hasPrefix("/iSHUSHL/CP24-Kiosk-NativeARM/releases/download/")
                  }) else { return nil }
            return (version, AvailableUpdate(version: release.tag_name, downloadURL: asset.browser_download_url))
        }.max(by: { $0.0 < $1.0 })?.1
    }

    static func fetch(newerThan current: String) async throws -> AvailableUpdate? {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/iSHUSHL/CP24-Kiosk-NativeARM/releases?per_page=100")!)
        request.timeoutInterval = 20
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("CP24-HLS-Kiosk/\(current)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "UpdateChecker", code: (response as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub could not be reached or the update request was limited. Try again later."])
        }
        return newest(in: try JSONDecoder().decode([GitHubRelease].self, from: data), newerThan: current)
    }
}
