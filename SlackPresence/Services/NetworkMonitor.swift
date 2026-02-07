import Foundation
import Network

@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "NetworkMonitor")

    var onConnectivityRestored: (() -> Void)?

    private init() {}

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let wasConnected = self?.isConnected ?? true
            let nowConnected = path.status == .satisfied

            DispatchQueue.main.async {
                self?.isConnected = nowConnected

                // Trigger callback when connectivity restored
                if !wasConnected && nowConnected {
                    self?.onConnectivityRestored?()
                }
            }
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
        onConnectivityRestored = nil  // Clear callback to release captured references
    }
}
