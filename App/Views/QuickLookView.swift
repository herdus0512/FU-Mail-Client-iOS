import FUMailKit
import SwiftUI

/// A Home Screen quick action's card (Rest of today, Pending drafts), over the conversations, asked for at
/// once without making a chat. Tapping a draft opens it in a new chat, with its Edit.
struct QuickLookView: View {
    var kind: QuickLook
    var client: RemoteClient
    var onOpenChat: (Conversation.ID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var answer: QuickLook.Answer?
    @State private var summary: String?
    @State private var summaryNote: String?
    @State private var summarizing = false
    @State private var speaker = Speaker()

    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    switch answer {
                    case nil:
                        ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                    case .problem(let text):
                        WarningText(text).frame(maxWidth: .infinity, alignment: .leading)
                    case .card(.events(let events)):
                        EventListCardView(card: events)
                    case .card(.draftList(let drafts)):
                        DraftListCardView(card: drafts,
                                          scope: CardScope(client: client, conversationID: UUID(), messageID: UUID(),
                                                           busy: false, connected: true)) { draft in
                            Task {
                                guard let id = await client.openDraftInNewChat(draft) else { return }
                                dismiss()
                                onOpenChat(id)
                            }
                        }
                    case .card:
                        EmptyView()
                    }
                    if case .card = answer { summarizeAndSpeak }
                }
                .padding(14)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(kind.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .topBarLeading) {
                    Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }
                        .accessibilityLabel("Ask again")
                }
            }
            .task { await load() }
            .onDisappear { speaker.stop() }
        }
    }

    /// One button, as on Android: the summary written on this iPhone, then read aloud. If it fails, it says
    /// why and doesn't speak. While speaking, it's Stop. Never starts by itself.
    private var summarizeAndSpeak: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                if speaker.isSpeaking { speaker.stop(); return }
                guard let answer else { return }
                summarizing = true
                summaryNote = nil
                Task {
                    switch await OnDeviceSummary.summarize(kind, lines: QuickLook.lines(answer)) {
                    case .success(let text):
                        summary = text
                        speaker.speak(text)
                    case .failure(let problem):
                        summaryNote = problem.message
                    }
                    summarizing = false
                }
            } label: {
                HStack(spacing: 6) {
                    if summarizing { ProgressView().controlSize(.small) }
                    Text(speaker.isSpeaking ? "Stop" : "Summarise & Speak")
                }
            }
            .buttonStyle(.bordered)
            .disabled(summarizing)
            if let summaryNote { WarningText(summaryNote) }
            if let summary {
                Text(summary).appFont(.subheadline)
                Text("Summary by Apple Intelligence, on this iPhone").appFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func load() async {
        speaker.stop()
        answer = nil
        summary = nil
        summaryNote = nil
        answer = await client.quickLook(kind)
    }
}

/// The quick action iOS opened the app with, for HomeView to show.
@MainActor
@Observable
final class QuickActions {
    static let shared = QuickActions()
    var pending: QuickLook?

    func take(_ item: UIApplicationShortcutItem?) {
        if let item, let kind = QuickLook(rawValue: item.type) { pending = kind }
    }
}

/// Hands iOS's quick actions to `QuickActions`: at launch, and while running.
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        QuickActions.shared.take(options.shortcutItem)
        let configuration = UISceneConfiguration(name: nil, sessionRole: session.role)
        configuration.delegateClass = QuickActionSceneDelegate.self
        return configuration
    }
}

final class QuickActionSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        QuickActions.shared.take(shortcutItem)
        completionHandler(QuickLook(rawValue: shortcutItem.type) != nil)
    }
}
