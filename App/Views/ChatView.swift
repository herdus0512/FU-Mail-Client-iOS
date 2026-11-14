import FUMailKit
import SwiftUI

/// One conversation: the provider line, the messages and cards, the chat status with Stop, and the
/// composer.
struct ChatView: View {
    let id: Conversation.ID
    let client: RemoteClient
    /// Beside the list (iPad), which shows the banners already.
    var sideBySide: Bool
    var onSettings: () -> Void

    private var conversation: Conversation? { client.state.conversation(id) }

    var body: some View {
        VStack(spacing: 0) {
            if !sideBySide { Banners(client: client) }
            if let line = client.state.info?.providerLine, !line.entries.isEmpty {
                ProviderLineRow(line: line)
            }
            content
            if let status = client.state.chatStatus[id] {
                ChatStatusLine(status: status) { client.stopAnswering(in: id) }
            }
            if conversation != nil {
                Composer(commands: client.state.commands) { client.send($0, in: id) }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(conversation?.title ?? "Conversation")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ConnectionIndicator(client: client, onSettings: onSettings)
            }
        }
        .onAppear { client.loadMessages(id) }
        .onChange(of: client.state.unloaded.contains(id)) { client.loadMessages(id) }
    }

    @ViewBuilder
    private var content: some View {
        if let conversation {
            if client.state.unloaded.contains(id) {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversation.messages.isEmpty {
                Text("Type a command such as /unread, /inbox, /search bob, /today or /help, or ask in plain words.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                MessageList(messages: conversation.messages, busy: client.state.busyMessages)
            }
        } else {
            ContentUnavailableView("Not on the Mac any more", systemImage: "bubble.left.and.exclamationmark.bubble.right",
                                   description: Text("This conversation was deleted, maybe on another device."))
        }
    }
}

/// The messages, opening at the newest. At the bottom, new messages and streaming cards stay in view;
/// scrolled up, they don't move you, and Latest jumps back down.
private struct MessageList: View {
    var messages: [ChatMessage]
    var busy: Set<ChatMessage.ID>

    @State private var atBottom = true
    /// Following the chat: true unless you scrolled up yourself. Decided when a scroll comes to rest,
    /// so new messages arriving (which grow the list) don't change it.
    @State private var following = true
    private let bottom = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { message in
                        MessageRow(message: message, busy: busy.contains(message.id))
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            .scrollDismissesKeyboard(.interactively)
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onScrollPhaseChange { _, phase in
                if phase == .idle { following = atBottom }
            }
            // Something new: while following, or when it's what you just sent, go to it.
            .onChange(of: messages.last?.id) {
                if following || messages.last?.role == .user {
                    following = true
                    proxy.scrollTo(bottom, anchor: .bottom)
                }
            }
            // A card growing (a summary streaming in) while following: stay at the bottom.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                if following { proxy.scrollTo(bottom, anchor: .bottom) }
            }
            .overlay(alignment: .bottomTrailing) {
                if !following && !atBottom {
                    Button {
                        following = true
                        withAnimation { proxy.scrollTo(bottom, anchor: .bottom) }
                    } label: {
                        Label("Latest", systemImage: "chevron.down").font(.caption.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.capsule)
                    .background(.regularMaterial, in: Capsule())
                    .padding(12)
                }
            }
        }
    }
}

private struct MessageRow: View {
    var message: ChatMessage
    var busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !message.text.isEmpty {
                switch message.role {
                case .user:
                    HStack {
                        Spacer(minLength: 48)
                        Text(message.text)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.accentColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 16))
                            .textSelection(.enabled)
                    }
                case .assistant:
                    Text(message.text).textSelection(.enabled)
                case .system:
                    Text(message.text)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .textSelection(.enabled)
                }
            }
            if let card = message.card {
                CardTextView(card: card, busy: busy)
            }
        }
    }
}

/// A card as text, until each card gets its own view with buttons (milestones 4–7).
private struct CardTextView: View {
    var card: Card
    var busy: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if busy {
                ProgressView().controlSize(.small)
            }
            Text(CardText.describe(card))
                .font(.footnote)
                .textSelection(.enabled)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator).opacity(0.5)))
    }
}

/// "Searching email (from Bob · last 2 days)…" with Stop, while the chat role works.
private struct ChatStatusLine: View {
    var status: String
    var onStop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.small)
            Text(status)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Stop", action: onStop)
                .font(.caption.weight(.medium))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// What's typed stays here until Send: a slash command or a question, both sent as they are. While
/// it's the start of a command ("/u"), the Mac's matching commands show above it; tapping one puts it
/// in the box, ready for its number or words.
private struct Composer: View {
    var commands: [Command]
    var onSend: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            let suggestions = Command.suggestions(text, from: commands)
            if !suggestions.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions) { command in
                            Button {
                                text = command.name + (command.args.isEmpty ? "" : " ")
                                focused = true
                            } label: {
                                CommandRow(command: command)
                            }
                            .buttonStyle(.plain)
                            Divider()
                        }
                    }
                }
                .frame(maxHeight: 220)
                .fixedSize(horizontal: false, vertical: true)
                .background(Color(.secondarySystemGroupedBackground))
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("/unread, or ask…", text: $text, axis: .vertical)
                    .lineLimit(1...5)
                    .focused($focused)
                    // Commands go as typed: no autocorrect turning "/unread" into something else.
                    .autocorrectionDisabled(text.hasPrefix("/"))
                    .textInputAutocapitalization(text.hasPrefix("/") ? .never : .sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 30))
                }
                .disabled(trimmed.isEmpty)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityLabel("Send")
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        text = ""
    }
}

private struct CommandRow: View {
    var command: Command

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(command.name).foregroundStyle(.tint)
                if !command.args.isEmpty {
                    Text(command.args).foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            if !command.summary.isEmpty {
                Text(command.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// Which provider each role uses on the Mac (a globe: off the Mac). Tap one for the details.
private struct ProviderLineRow: View {
    var line: ProviderLine
    @State private var shown: ProviderLine.Entry?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(line.entries) { entry in
                    Button {
                        shown = entry
                    } label: {
                        Label(entry.label, systemImage: entry.remote ? "globe" : "laptopcomputer")
                            .font(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(entry.remote ? "Off the Mac" : "On the Mac")
                    .popover(isPresented: Binding(get: { shown == entry }, set: { if !$0 { shown = nil } })) {
                        ScrollView {
                            Text(entry.details)
                                .font(.caption)
                                .textSelection(.enabled)
                                .padding()
                        }
                        .frame(idealWidth: 360, maxHeight: 400)
                        .presentationCompactAdaptation(.popover)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .background(.bar)
    }
}
