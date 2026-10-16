import Foundation
import Network

final class NetworkMonitor {
    static let shared = NetworkMonitor()

    var statusChanged: ((Bool, String) -> Void)?

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NewsTVKiosk.NetworkMonitor")
    private var started = false

    private init() {}

    func start() {
        guard !started else { return }
        started = true
        monitor.pathUpdateHandler = { [weak self] path in
            let isOnline = path.status == .satisfied
            let detail: String
            if path.status == .satisfied {
                detail = path.isExpensive ? "Online, metered" : "Online"
            } else if path.status == .requiresConnection {
                detail = "Waiting for connection"
            } else {
                detail = "Offline"
            }

            DispatchQueue.main.async {
                self?.statusChanged?(isOnline, detail)
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        guard started else { return }
        monitor.cancel()
        started = false
    }
}
