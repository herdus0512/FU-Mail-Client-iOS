import AppIntents
import FUMailKit
import Foundation

/// "Rest of Today" for Siri and Shortcuts: what's left of today's calendar, from FU Mail on the Mac,
/// with the app's own saved connection (no token ever goes into a shortcut). Runs without opening the
/// app; returns the lines as text (for "Use Model", say), and Siri reads them out.
struct RestOfTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Rest of Today"
    static let description = IntentDescription("What's left of today's calendar, from FU Mail")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let text: String
        if let settings = StoredConnection.settings() {
            text = await RestOfToday.fetch(DesktopAPI(settings: settings))
        } else {
            text = RestOfToday.notSetUp
        }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// "Pending Drafts": the unsent drafts across accounts, from FU Mail, the same way as Rest of Today.
struct PendingDraftsIntent: AppIntent {
    static let title: LocalizedStringResource = "Pending Drafts"
    static let description = IntentDescription("Your unsent drafts across accounts, from FU Mail")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        var text = RestOfToday.notSetUp
        if let settings = StoredConnection.settings() { text = await PendingDrafts.fetch(DesktopAPI(settings: settings)) }
        return .result(value: text, dialog: IntentDialog(stringLiteral: text))
    }
}

/// In Shortcuts and Siri without any setup.
struct FUMailShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RestOfTodayIntent(),
                    phrases: ["What's left today in \(.applicationName)", "Rest of today in \(.applicationName)"],
                    shortTitle: "Rest of Today",
                    systemImageName: "calendar")
        AppShortcut(intent: PendingDraftsIntent(),
                    phrases: ["Pending drafts in \(.applicationName)", "Drafts waiting in \(.applicationName)"],
                    shortTitle: "Pending Drafts",
                    systemImageName: "envelope.badge")
    }
}

/// The connection Settings saved: the address, and the device and Cloudflare Access tokens from the
/// Keychain. nil when the app hasn't been set up (or the phone hasn't been unlocked since starting up).
enum StoredConnection {
    static func settings() -> ServerSettings? {
        guard let address = UserDefaults.standard.string(forKey: "tailscaleURL"), !address.isEmpty,
              let token = TokenStore.load(),
              case .success(var settings) = ServerSettings.parse(url: address, token: token) else { return nil }
        settings.access = TokenStore.loadAccess()
        return settings
    }
}
