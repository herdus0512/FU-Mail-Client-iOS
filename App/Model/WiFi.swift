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

/// Watches the network. No permission is needed and no Wi-Fi name (SSID) is read.
///
/// - **Wi-Fi:** a monitor for the Wi-Fi interface only, satisfied while Wi-Fi is up. A VPN running
///   over it (Tailscale) doesn't hide it, as it can from the device's main network path, where iOS may
///   report only the VPN's interface.
/// - **Any change:** the main path, which changes when a VPN comes or goes as well (Wi-Fi itself
///   unchanged). That's when the home address may have become reachable again.
@MainActor
final class NetworkWatcher {
    private let wifiMonitor = NWPathMonitor(requiredInterfaceType: .wifi)
    private let anyMonitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.h3rdus.fumail.network")
    private let onWifiReading: @MainActor (Bool) -> Void
    private let onChange: @MainActor () -> Void

    /// `onWifiReading` gets every Wi-Fi reading (the first one soon after `start`); `onChange` any
    /// change of the main path after the first.
    init(onWifiReading: @escaping @MainActor (Bool) -> Void, onChange: @escaping @MainActor () -> Void) {
        self.onWifiReading = onWifiReading
        self.onChange = onChange
    }

    func start() {
        wifiMonitor.pathUpdateHandler = { [weak self] path in
            let onWifi = path.status == .satisfied
            Task { @MainActor in self?.onWifiReading(onWifi) }
        }
        let seenFirst = Mutex(false)
        anyMonitor.pathUpdateHandler = { [weak self] _ in
            // The first update only says how things are now; later ones are changes.
            guard seenFirst.withLock({ seen in defer { seen = true }; return seen }) else { return }
            Task { @MainActor in self?.onChange() }
        }
        wifiMonitor.start(queue: queue)
        anyMonitor.start(queue: queue)
    }

    deinit {
        wifiMonitor.cancel()
        anyMonitor.cancel()
    }
}
