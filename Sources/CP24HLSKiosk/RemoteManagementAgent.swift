import Foundation

/// Optional remote-management transport. Never blocks playback or recovery.
@MainActor
final class RemoteManagementAgent {
    struct Command: Decodable {
        let id: Int
        let action: String
        let channel: String?
        let intervalMinutes: Int?
    }

    struct PollResponse: Decodable {
        let command: Command?
    }

    struct Status: Encodable {
        let deviceId: String
        let channel: String
        let playbackHealthy: Bool
        let appVersion: String
        let uptimeSeconds: Int
    }

    private var timer: Timer?
    private var busy = false
    private let session: URLSession
    private let status: () -> Status
    private let execute: (Command) async -> Bool

    init(status: @escaping () -> Status, execute: @escaping (Command) async -> Bool) {
        self.status = status
        self.execute = execute
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        config.timeoutIntervalForResource = 12
        self.session = URLSession(configuration: config)
    }

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.poll() }
        }
        Task { await poll() }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func poll() async {
        guard !busy else { return }
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: "RemoteManagementEnabled"),
              let rawURL = defaults.string(forKey: "RemoteManagementServerURL"),
              let baseURL = URL(string: rawURL),
              baseURL.scheme == "https",
              let host = baseURL.host, !host.isEmpty,
              let token = defaults.string(forKey: "RemoteManagementDeviceToken"),
              !token.isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let endpoint = baseURL.appendingPathComponent("api/device-poll.php")
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(status())
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }
            let poll = try JSONDecoder().decode(PollResponse.self, from: data)
            if let command = poll.command {
                let succeeded = await execute(command)
                await acknowledge(command.id, succeeded: succeeded, baseURL: baseURL, token: token)
            }
        } catch {
            // A management outage must never interrupt local video playback.
        }
    }

    private func acknowledge(_ id: Int, succeeded: Bool, baseURL: URL, token: String) async {
        let endpoint = baseURL.appendingPathComponent("api/device-ack.php")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \\(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["commandId": id, "success": succeeded])
        _ = try? await session.data(for: request)
    }
}
