import Foundation

final class CrashWatchdog {
    static let shared = CrashWatchdog()

    private let sessionID = UUID().uuidString
    private var stopFlagURL: URL?

    private init() {}

    func start() {
        let supportURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("CP24 HLS Kiosk", isDirectory: true)
            ?? FileManager.default.temporaryDirectory.appendingPathComponent("CP24 HLS Kiosk", isDirectory: true)
        let watchdogURL = supportURL.appendingPathComponent("Watchdog", isDirectory: true)
        let stopFlagURL = watchdogURL.appendingPathComponent("\(sessionID).stop")
        self.stopFlagURL = stopFlagURL

        do {
            try FileManager.default.createDirectory(at: watchdogURL, withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: stopFlagURL)
            try launchMonitor(stopFlagURL: stopFlagURL)
            StreamHealthLog.append("Crash watchdog started")
        } catch {
            StreamHealthLog.append("Crash watchdog failed to start: \(error.localizedDescription)")
        }
    }

    func markIntentionalShutdown() {
        guard let stopFlagURL else { return }
        do {
            try "intentional shutdown\n".write(to: stopFlagURL, atomically: true, encoding: .utf8)
            StreamHealthLog.append("Crash watchdog marked intentional shutdown")
        } catch {
            StreamHealthLog.append("Crash watchdog stop flag failed: \(error.localizedDescription)")
        }
    }

    private func launchMonitor(stopFlagURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            "-c",
            Self.monitorScript,
            "news-tv-kiosk-watchdog",
            "\(ProcessInfo.processInfo.processIdentifier)",
            Bundle.main.bundleURL.path,
            stopFlagURL.path,
            StreamHealthLog.logURL.path
        ]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
    }

    private static let monitorScript = #"""
parent_pid="$1"
app_bundle="$2"
stop_flag="$3"
log_file="$4"

log_event() {
  mkdir -p "$(dirname "$log_file")"
  printf "%s  %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$log_file"
}

while kill -0 "$parent_pid" 2>/dev/null; do
  sleep 5
done

if [ -f "$stop_flag" ]; then
  log_event "Crash watchdog stopped: intentional shutdown"
  rm -f "$stop_flag"
  exit 0
fi

log_event "Crash watchdog detected unexpected app exit; relaunching"
sleep 2
/usr/bin/open -n "$app_bundle"
"""#
}
