import FUMailKit
import SwiftUI

/// The conversations, newest first, with history search across them. Swipe to delete; touch and
/// hold to rename.
struct ConversationListView: View {
    @Environment(AppModel.self) private var app
    @Binding var selection: Conversation.ID?
    /// Set with a history search result: the message that matched.
    @Binding var jumpTo: MessageJump?
    /// The list and the chat side by side (iPad): the indicator sits over the chat then.
    var sideBySide: Bool
    var onSettings: () -> Void

    @State private var query = ""
    @State private var hits: [SearchHit]?
    @State private var searchProblem: String?
    @State private var renaming: Conversation?
    @State private var newTitle = ""
    @State private var deleting: Conversation?

    var body: some View {
        VStack(spacing: 0) {
            Banners(client: app.client)
            if let client = app.client {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    conversations(client)
                } else {
                    searchResults
                }
            } else {
                NotSetUp(onSettings: onSettings)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("FU Mail")
        .toolbar {
            // Side by side (iPad), the indicator sits over the chat, leaving the narrow column room.
            if !sideBySide {
                ToolbarItem(placement: .topBarLeading) {
                    ConnectionIndicator(client: app.client, onSettings: onSettings)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onSettings) { Image(systemName: "gearshape") }
                    .accessibilityLabel("Settings")
            }
            if let client = app.client {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { if let id = await client.startConversation() { selection = id } }
                    } label: {
                        Image(systemName: "square.and.pencil")
                    }
                    .accessibilityLabel("New conversation")
                    .keyboardShortcut("n", modifiers: .command)
                }
            }
        }
        .searchable(text: $query, prompt: "Search history")
        .task(id: query) { await search() }
        .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Title", text: $newTitle)
            Button("Rename") {
                if let renaming { app.client?.rename(renaming.id, to: newTitle) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .confirmationDialog("Delete “\(deleting?.title ?? "")”?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                guard let deleting, let client = app.client else { return }
                if selection == deleting.id { selection = nil }
                client.delete(deleting.id)
            }
        } message: {
            Text("It's deleted from the Mac's history too.")
        }
    }

    @ViewBuilder
    private func conversations(_ client: RemoteClient) -> some View {
        let conversations = client.state.conversations
        if conversations.isEmpty {
            ContentUnavailableView {
                Label(client.state.connection.connected ? "No conversations" : "Connecting…",
                      systemImage: "bubble.left.and.bubble.right")
            } description: {
                Text(client.state.connection.connected ? "Start one with the pencil." : client.display)
            }
        } else {
            List(selection: $selection) {
                ForEach(conversations) { conversation in
                    ConversationRow(conversation: conversation, answering: client.state.isAnswering(conversation.id))
                        .tag(conversation.id)
                        .swipeActions {
                            Button("Delete", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                        .contextMenu {
                            Button("Rename…", systemImage: "pencil") {
                                newTitle = conversation.title
                                renaming = conversation
                            }
                            Button("Delete…", systemImage: "trash", role: .destructive) { deleting = conversation }
                        }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        if let searchProblem {
            WarningText(searchProblem).padding()
            Spacer()
        } else if let hits {
            if hits.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(hits) { hit in
                    Button {
                        jumpTo = hit.messageID.map { MessageJump(conversationID: hit.conversationID, messageID: $0) }
                        selection = hit.conversationID
                    } label: {
                        SearchHitRow(hit: hit)
                    }
                    .tint(.primary)
                }
                .listStyle(.insetGrouped)
            }
        } else {
            ProgressView().padding()
            Spacer()
        }
    }

    /// History search: after a short pause in typing, not per keystroke.
    private func search() async {
        let words = query.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty, let client = app.client else {
            hits = nil
            searchProblem = nil
            return
        }
        try? await Task.sleep(for: .milliseconds(350))
        guard !Task.isCancelled else { return }
        do {
            hits = try await client.searchHistory(words)
            searchProblem = nil
        } catch is CancellationError {
        } catch {
            searchProblem = (error as? RemoteProblem)?.message ?? error.localizedDescription
        }
    }
}

private struct ConversationRow: View {
    var conversation: Conversation
    var answering: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title).lineLimit(1)
                Text(conversation.updatedAt, format: .relative(presentation: .named))
                    .appFont(.caption)
                    .foregroundStyle(.secondary)
            }
            if answering {
                Spacer()
                ProgressView().controlSize(.small)
            }
        }
    }
}

private struct SearchHitRow: View {
    var hit: SearchHit

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(hit.title).lineLimit(1)
                Spacer()
                if hit.byMeaning == true {
                    Text("by meaning").appFont(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(Self.highlighted(hit.snippet))
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
            Text(hit.updatedAt, format: .relative(presentation: .named))
                .appFont(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// The matched words, which the Mac puts between « and », in bold.
    static func highlighted(_ snippet: String) -> AttributedString {
        var result = AttributedString()
        var bold = false
        var part = ""
        func flush() {
            var piece = AttributedString(part)
            if bold { piece.font = .caption.bold() }
            result += piece
            part = ""
        }
        for character in snippet {
            if character == "«" || character == "»" {
                flush()
                bold = character == "«"
            } else {
                part.append(character)
            }
        }
        flush()
        return result
    }
}

struct NotSetUp: View {
    var onSettings: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("Not set up", systemImage: "desktopcomputer")
        } description: {
            Text("FU Mail shows the conversations of FU Mail on your Mac. Add the Mac's address and a device token to connect.")
        } actions: {
            Button("Settings", action: onSettings).buttonStyle(.borderedProminent)
        }
    }
}
