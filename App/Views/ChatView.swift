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
                MessageList(messages: conversation.messages, busy: client.state.busyMessages, client: client, conversationID: id)
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
    var client: RemoteClient
    var conversationID: Conversation.ID

    @State private var atBottom = true
    /// Following the chat: true unless you scrolled up yourself. Decided when a scroll comes to rest,
    /// so new messages arriving (which grow the list) don't change it.
    @State private var following = true
    /// How many of the newest messages are shown. A long chat opens with the newest few, and "Show
    /// earlier messages" adds more: laying out a whole long history (long emails) made opening and
    /// scrolling slow.
    @State private var limit = Self.page
    private let bottom = "bottom"
    private static let page = 20

    /// Every message there is to show (`make run-fake UPTO=6`: only the first few, so the ones wanted
    /// for a screenshot end up at the bottom; debug builds only).
    private var all: [ChatMessage] {
        #if DEBUG
        if let upTo = ProcessInfo.processInfo.environment["FUMAIL_UPTO"].flatMap(Int.init) {
            return Array(messages.prefix(upTo))
        }
        #endif
        return messages
    }

    var body: some View {
        let all = self.all
        let shown = all.suffix(limit)
        let earlier = all.count - shown.count
        ScrollViewReader { proxy in
            ScrollView {
                // Not lazy: a lazy stack estimates the height of messages off screen, and with long
                // emails a jump to the bottom (a new message, a card growing) could land past the real
                // end and show nothing until the chat was opened again. Showing only the newest
                // messages keeps that cheap.
                VStack(alignment: .leading, spacing: 12) {
                    if earlier > 0 {
                        Button {
                            let firstShown = shown.first?.id
                            limit += Self.page
                            // Stay where you were: the earlier messages appear above it.
                            if let firstShown {
                                Task { proxy.scrollTo(firstShown, anchor: .top) }
                            }
                        } label: {
                            Label("Show earlier messages (\(earlier))", systemImage: "chevron.up")
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .padding(.bottom, 4)
                    }
                    ForEach(shown) { message in
                        // Equatable: a message that didn't change isn't rebuilt when another one does
                        // (a summary streaming in, a status line), which keeps scrolling smooth.
                        MessageRow(message: message,
                                   scope: CardScope(client: client, conversationID: conversationID, messageID: message.id,
                                                    busy: busy.contains(message.id)))
                            .equatable()
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            // The keyboard goes away when the messages are scrolled or tapped.
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onScrollPhaseChange { _, phase in
                if phase == .idle { following = atBottom }
            }
            .onChange(of: messages.last?.id) { reveal(proxy) }
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

extension MessageList {
    /// Something new at the bottom. What you just sent goes into view. A card that answers something
    /// asked for here (an email opened, a command, Add to note) is shown from its start, even when the
    /// chat was scrolled up, so an opened email is read from the top. Anything else is shown only while
    /// following the chat.
    fileprivate func reveal(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        if last.role == .user {
            following = true
            proxy.scrollTo(bottom, anchor: .bottom)
            return
        }
        let asked = client.takeExpectedReply(in: conversationID)
        guard following || asked else { return }
        guard last.card != nil else {
            following = true
            proxy.scrollTo(bottom, anchor: .bottom)
            return
        }
        // From its top. A long card (an email) then isn't pulled down to its end as the chat would be
        // while following; a short one ends at the bottom anyway, and the chat follows again.
        following = false
        proxy.scrollTo(last.id, anchor: .top)
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            following = atBottom
        }
    }
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct MessageRow: View, Equatable {
    var message: ChatMessage
    var scope: CardScope

    nonisolated static func == (a: MessageRow, b: MessageRow) -> Bool {
        MainActor.assumeIsolated { a.message == b.message && a.scope.busy == b.scope.busy && a.scope.messageID == b.scope.messageID }
    }

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
                CardView(card: card, scope: scope)
            }
        }
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
                // The standard iOS font here, for typing (the placeholder takes its font on its own).
                TextField("", text: $text, prompt: Text("/unread, or ask…").font(.body).fontDesign(.default), axis: .vertical)
                    .lineLimit(1...5)
                    .font(.body)
                    .fontDesign(.default)
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
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { focused = false }
                }
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
