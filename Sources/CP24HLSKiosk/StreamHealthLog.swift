import Foundation

enum StreamHealthLog {
    private static let maxLogBytes = 1_000_000
    private static let retentionDays = 30

    static var logURL: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return baseURL
            .appendingPathComponent("CP24 HLS Kiosk", isDirectory: true)
            .appendingPathComponent("stream-health.log")
    }

    static func append(_ message: String) {
        let line = "\(Self.timestamp())  \(message)\n"
        let url = logURL

        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            pruneOldEntries(at: url)
            rotateIfNeeded(at: url)
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                try handle.seekToEnd()
                if let data = line.data(using: .utf8) {
                    try handle.write(contentsOf: data)
                }
            } else {
                try line.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            NSLog("CP24 HLS Kiosk health log failed: \(error.localizedDescription)")
        }
    }

    static func read() -> String {
        (try? String(contentsOf: logURL, encoding: .utf8)) ?? "No stream health events recorded yet."
    }

    static func clear() {
        try? FileManager.default.removeItem(at: logURL)
        append("Health log cleared")
    }

    private static func pruneOldEntries(at url: URL) {
        guard
            let content = try? String(contentsOf: url, encoding: .utf8),
            !content.isEmpty
        else {
            return
        }

        let cutoff = Date().addingTimeInterval(TimeInterval(-retentionDays * 24 * 60 * 60))
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let keptLines = lines.filter { line in
            guard line.count >= 19 else { return true }
            let timestamp = String(line.prefix(19))
            guard let date = logDateFormatter.date(from: timestamp) else { return true }
            return date >= cutoff
        }

        guard keptLines.count != lines.count else { return }
        try? keptLines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }

    private static func rotateIfNeeded(at url: URL) {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attributes[.size] as? NSNumber,
            size.intValue > maxLogBytes,
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return
        }

        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let keptLines = lines.suffix(2_000).joined(separator: "\n")
        try? keptLines.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func timestamp() -> String {
        logDateFormatter.string(from: Date())
    }

    private static let logDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.timeZone = .current
        return formatter
    }()
}
