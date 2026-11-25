import FUMailKit
import SwiftUI

/// One conversation: the provider line, the messages and cards, the chat status with Stop, and the
/// composer.
struct ChatView: View {
    let id: Conversation.ID
    let client: RemoteClient
    /// A history search result's message: scrolled to once the messages are shown.
    @Binding var jumpTo: MessageJump?
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
        #if DEBUG
        // `make run-fake SEND=/unread`: sends it a moment after the chat opens, for checking how its
        // answer lands without typing into the Simulator. Debug only.
        .task {
            guard let command = ProcessInfo.processInfo.environment["FUMAIL_SEND"] else { return }
            try? await Task.sleep(for: .seconds(2))
            client.send(command, in: id)
        }
        #endif
        .onChange(of: client.state.unloaded.contains(id)) { client.loadMessages(id) }
    }

    @ViewBuilder
    private var content: some View {
        if let conversation {
            if client.state.unloaded.contains(id) {
                ProgressView("Loading…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if conversation.messages.isEmpty {
                Text("Type a command such as /unread, /inbox, /search bob, /today or /help, or ask in plain words.")
                    .appFont(.callout)
                    .foregroundStyle(.secondary)
                    .padding(24)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    // A new chat has no messages to tap or drag: a tap anywhere here hides the keyboard.
                    .contentShape(Rectangle())
                    .onTapGesture { hideKeyboard() }
            } else {
                MessageList(messages: conversation.messages, busy: client.state.busyMessages, client: client, conversationID: id,
                            jumpTo: $jumpTo)
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
    @Binding var jumpTo: MessageJump?

    @State private var atBottom = true
    /// Lit up briefly after a jump to it from history search.
    @State private var highlighted: ChatMessage.ID?
    /// The newest message, kept with its top at the top of the screen while it changes: the Mac
    /// answers with a small placeholder ("Opening…") that then becomes the card, which may then
    /// grow. Ends as soon as you scroll yourself.
    @State private var landing: ChatMessage.ID?
    /// You just sent something: its answer is landed on even if the chat wasn't following.
    @State private var answerAwaited = false
    /// Following the chat: true unless you scrolled up yourself. Decided when a scroll comes to rest,
    /// so new messages arriving (which grow the list) don't change it.
    @State private var following = true
    /// How many of the newest messages are shown. A long chat opens with the newest few, and "Show
    /// earlier messages" adds more: laying out a whole long history (long emails) made opening and
    /// scrolling slow.
    @State private var limit = Self.page
    private let bottom = "bottom"
    private static let page = 10

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
                            landing = nil  // you're reading back now
                            limit += Self.page
                            // Stay where you were: the earlier messages appear above it.
                            if let firstShown {
                                Task { proxy.scrollTo(firstShown, anchor: .top) }
                            }
                        } label: {
                            Label("Show earlier messages (\(earlier))", systemImage: "chevron.up")
                                .appFont(.subheadline, weight: .medium)
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
                                                    busy: busy.contains(message.id),
                                                    connected: client.state.connection.connected))
                            .equatable()
                            .background(RoundedRectangle(cornerRadius: 10)
                                .fill(Color.accentColor.opacity(highlighted == message.id ? 0.15 : 0))
                                .padding(-4)
                                .animation(.easeOut(duration: 0.3), value: highlighted))
                            .id(message.id)
                    }
                    Color.clear.frame(height: 1).id(bottom)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .defaultScrollAnchor(.bottom)
            // The keyboard goes away as soon as the chat is scrolled (a card dragged included) or the
            // messages are tapped, and after sending. No Done bar above it: iOS floats that over the
            // message bar.
            .scrollDismissesKeyboard(.immediately)
            .simultaneousGesture(TapGesture().onEnded { hideKeyboard() })
            .onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentOffset.y + geometry.containerSize.height >= geometry.contentSize.height - 60
            } action: { _, isAtBottom in
                atBottom = isAtBottom
            }
            .onScrollPhaseChange { _, phase in
                // Your own scrolling or dragging ends a landing (a scroll made here doesn't).
                if phase == .tracking || phase == .interacting { landing = nil }
                if phase == .idle, landing == nil { following = atBottom }
            }
            .onChange(of: messages.last?.id) { reveal(proxy) }
            // The message being landed on changed (placeholder → card, a card growing): its top again.
            .onChange(of: messages.last) {
                if let landing, messages.last?.id == landing { proxy.scrollTo(landing, anchor: .top) }
            }
            // A history search result: show back to its message, then scroll to it.
            .onAppear { jump(proxy) }
            .onChange(of: jumpTo) { jump(proxy) }
            // Laid out taller (a card arriving, a summary streaming in): the landed message's top stays
            // in view, or while following, the chat stays at the bottom.
            .onScrollGeometryChange(for: CGFloat.self) { $0.contentSize.height } action: { _, _ in
                if let landing {
                    proxy.scrollTo(landing, anchor: .top)
                } else if following {
                    proxy.scrollTo(bottom, anchor: .bottom)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if !following && !atBottom && landing == nil {
                    Button {
                        landing = nil
                        following = true
                        withAnimation { proxy.scrollTo(bottom, anchor: .bottom) }
                    } label: {
                        Label("Latest", systemImage: "chevron.down").appFont(.caption, weight: .medium)
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
    /// To the message a history search found, as the Mac does: earlier messages are shown back to
    /// it, it comes to the middle, and it lights up for a moment. An id not in this chat is let go.
    fileprivate func jump(_ proxy: ScrollViewProxy) {
        guard let jump = jumpTo, jump.conversationID == conversationID else { return }
        jumpTo = nil
        let target = jump.messageID
        guard let index = all.firstIndex(where: { $0.id == target }) else { return }
        limit = max(limit, all.count - index)
        landing = nil
        following = false
        // After the bottom-scroll of opening, and after the messages shown back are laid out.
        Task {
            try? await Task.sleep(for: .milliseconds(150))
            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(target, anchor: .center) }
            highlighted = target
            try? await Task.sleep(for: .seconds(1.5))
            if highlighted == target { highlighted = nil }
        }
    }

    /// Something new at the bottom. What you just sent goes into view. The answer that follows (or a
    /// new message while you're at the bottom, or one answering something asked for here: an email
    /// opened, Add to note…) is landed on: its top at the top of the screen, kept there while the
    /// placeholder becomes the card and the card grows, until you scroll yourself, as on the Mac.
    /// Anything else leaves you where you are.
    fileprivate func reveal(_ proxy: ScrollViewProxy) {
        guard let last = messages.last else { return }
        if last.role == .user {
            landing = nil
            following = true
            answerAwaited = true
            proxy.scrollTo(bottom, anchor: .bottom)
            return
        }
        let asked = client.takeExpectedReply(in: conversationID)
        guard following || asked || answerAwaited || landing != nil else { return }
        answerAwaited = false
        landing = last.id
        following = false
        proxy.scrollTo(last.id, anchor: .top)
    }
}

/// A message to scroll to once its chat is open (a history search result).
struct MessageJump: Equatable {
    var conversationID: Conversation.ID
    var messageID: ChatMessage.ID
}

@MainActor
func hideKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}

private struct MessageRow: View, Equatable {
    var message: ChatMessage
    var scope: CardScope

    nonisolated static func == (a: MessageRow, b: MessageRow) -> Bool {
        MainActor.assumeIsolated {
            a.message == b.message && a.scope.busy == b.scope.busy && a.scope.connected == b.scope.connected
                && a.scope.messageID == b.scope.messageID
        }
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
                            .copyable(message.text)
                    }
                case .assistant:
                    // A step under what you typed, at the cards' size, as in the Android app.
                    Text(message.text).appFont(.subheadline).copyable(message.text)
                case .system:
                    Text(message.text)
                        .appFont(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .copyable(message.text)
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
                .appFont(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Stop", action: onStop)
                .appFont(.caption, weight: .medium)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.bar)
    }
}

/// What's typed stays here until Send: a slash command or a question, both sent as they are. Tapping
/// into the empty box shows every command above it; while it's the start of a command ("/u"), the
/// Mac's matching ones; tapping one puts it in the box, ready for its number or words.
private struct Composer: View {
    var commands: [Command]
    var onSend: (String) -> Void

    @State private var text = ""
    @FocusState private var focused: Bool
    /// For the placeholder, which has to be plain text (see `TextSize`).
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @AppStorage("textSize") private var textSize: TextSize = .standard
    /// Every command, shown when you tap into the empty box (typing "/" on a phone is awkward). Not
    /// after sending, when the box is empty and still has the cursor: that would cover the answer.
    @State private var showAll = false

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(spacing: 0) {
            let suggestions = text.isEmpty && showAll ? commands : Command.suggestions(text, from: commands)
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
                // SF Mono, as everywhere else (and in the Android app).
                TextField("", text: $text, prompt: Text("/unread, or ask…").font(.system(size: AppFont.size(.body, dynamicTypeSize, textSize))), axis: .vertical)
                    .lineLimit(1...5)
                    .appFont(.body)
                    .focused($focused)
                    // Tapping into the box, as it gets the cursor or again once it has it.
                    .simultaneousGesture(TapGesture().onEnded { if text.isEmpty { showAll = true } })
                    .onChange(of: focused) { _, now in showAll = now && text.isEmpty }
                    // Typing narrows the list as before; emptying the box again doesn't bring it all back.
                    .onChange(of: text) { if !text.isEmpty { showAll = false } }
                    // Commands go as typed: no autocorrect turning "/unread" into something else, nor
                    // (while it's the first word) "obs" into "obs." before its command can be picked.
                    .autocorrectionDisabled(text.hasPrefix("/") || !Command.suggestions(text, from: commands).isEmpty)
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
        #if DEBUG
        // `make run-fake FOCUS=1`: the cursor in the box a moment after the chat opens, for checking
        // it with the on-screen keyboard without tapping into the Simulator. Debug only.
        .task {
            guard ProcessInfo.processInfo.environment["FUMAIL_FOCUS"] != nil else { return }
            try? await Task.sleep(for: .seconds(1.5))
            focused = true
        }
        #endif
    }

    private func send() {
        guard !trimmed.isEmpty else { return }
        onSend(trimmed)
        showAll = false
        text = ""
        // The answer is to read (often a card): the keyboard makes way for it. Tap the box to type again.
        focused = false
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
            .appFont(.callout)
            if !command.summary.isEmpty {
                Text(command.summary).appFont(.caption).foregroundStyle(.secondary).lineLimit(2)
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
                            .appFont(.caption2)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(entry.remote ? "Off the Mac" : "On the Mac")
                    .popover(isPresented: Binding(get: { shown == entry }, set: { if !$0 { shown = nil } })) {
                        ScrollView {
                            Text(entry.details)
                                .appFont(.caption)
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
