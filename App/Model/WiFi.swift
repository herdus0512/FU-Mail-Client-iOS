import Foundation
import Network
import Synchronization

/// Whether this device is on Wi-Fi right now, readable from any thread (the address picker asks it
/// while connecting).
final class WiFiState: Sendable {
    private let value = Mutex(false)

    var onWifi: Bool { value.withLock { $0 } }

    func set(_ onWifi: Bool) { value.withLock { $0 = onWifi } }
}

/// Watches the system's network path for Wi-Fi coming and going. No permission is needed and no Wi-Fi
/// name (SSID) is read: only "is Wi-Fi one of this path's interfaces". Wi-Fi counts as Wi-Fi while a
/// VPN (Tailscale) runs over it, since the Wi-Fi interface is still there under the VPN's.
@MainActor
final class WiFiWatcher {
    private let monitor = NWPathMonitor()
    private let onReading: @MainActor (Bool) -> Void

    /// `onReading` gets every reading (the first one soon after `start`); the caller decides what's a change.
    init(onReading: @escaping @MainActor (Bool) -> Void) {
        self.onReading = onReading
    }

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let onWifi = path.availableInterfaces.contains { $0.type == .wifi }
            Task { @MainActor in self?.onReading(onWifi) }
        }
        monitor.start(queue: DispatchQueue(label: "com.h3rdus.fumail.wifi"))
    }

    deinit {
        monitor.cancel()
    }
}
