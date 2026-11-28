import AppIntents
import FUMailKit
import Foundation
import SwiftUI

/// "Rest of Today" for Siri and Shortcuts: what's left of today's calendar, from FU Mail on the Mac,
/// with the app's own saved connection (no token ever goes into a shortcut). Runs without opening the
/// app; returns the lines as text (for "Use Model", say), and Siri reads them out.
struct RestOfTodayIntent: AppIntent {
    static let title: LocalizedStringResource = "Rest of Today"
    static let description = IntentDescription("What's left of today's calendar, from FU Mail")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        await SpokenAnswer.answer(.restOfToday)
    }
}

/// "Pending Drafts": the unsent drafts across accounts, from FU Mail, the same way as Rest of Today.
struct PendingDraftsIntent: AppIntent {
    static let title: LocalizedStringResource = "Pending Drafts"
    static let description = IntentDescription("Your unsent drafts across accounts, from FU Mail")
    static let openAppWhenRun = false

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        await SpokenAnswer.answer(.pendingDrafts)
    }
}

/// An answer for Siri: a concise count (`QuickLook.siriSummary`), while the card under Siri's reply
/// and the shortcut's output keep the full list.
enum SpokenAnswer {
    static func answer(_ kind: QuickLook) async -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        guard let settings = StoredConnection.settings() else { return result(RestOfToday.notSetUp, spoken: RestOfToday.notSetUp) }
        let answer = await kind.fetch(DesktopAPI(settings: settings, auth: StoredConnection.workerAuth()))
        return result(QuickLook.lines(answer), spoken: QuickLook.siriSummary(answer))
    }

    static func result(_ text: String, spoken: String) -> some IntentResult & ReturnsValue<String> & ProvidesDialog & ShowsSnippetView {
        .result(value: text, dialog: IntentDialog(stringLiteral: spoken), view: AnswerView(text: text))
    }
}

/// The answer as written, under Siri's reply.
private struct AnswerView: View {
    var text: String

    var body: some View {
        Text(text)
            .font(.callout)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }
}

/// In Shortcuts and Siri without any setup.
struct FUMailShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: RestOfTodayIntent(),
                    phrases: ["What's left in \(.applicationName)",
                              "What's left today in \(.applicationName)",
                              "Rest of today in \(.applicationName)"],
                    shortTitle: "Rest of Today",
                    systemImageName: "calendar")
        AppShortcut(intent: PendingDraftsIntent(),
                    // Some without "draft", which Messages and Mail answer to as well.
                    phrases: ["What's pending in \(.applicationName)",
                              "Pending drafts in \(.applicationName)",
                              "What's waiting to send in \(.applicationName)",
                              "Unsent emails in \(.applicationName)"],
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
              case .success(let settings) = ServerSettings.parse(url: address, token: token) else { return nil }
        return settings
    }

    static func workerAuth() -> WorkerAuthStore? {
        guard let session = TokenStore.loadWorkerSession() else { return nil }
        return WorkerAuthStore(session: session) { updated, _ in
            try? TokenStore.saveWorkerSession(updated)
        }
    }
}
