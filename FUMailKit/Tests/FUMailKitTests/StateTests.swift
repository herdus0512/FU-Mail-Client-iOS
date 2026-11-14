import Foundation
import Testing
@testable import FUMailKit

private func msg(_ name: String, _ text: String = "", role: ChatMessage.Role = .assistant, card: Card? = nil,
                 at: Date = t0) -> ChatMessage {
    ChatMessage(id: id(name), role: role, text: text, card: card, createdAt: at)
}

private func conv(_ name: String, _ messages: ChatMessage..., title: String? = nil) -> Conversation {
    Conversation(id: id(name), title: title ?? "Chat \(name)", createdAt: t0, updatedAt: t0, messages: messages)
}

private func loaded(_ conversations: Conversation...) -> RemoteState {
    var state = RemoteState()
    state.conversations = conversations
    return state
}

private func editor(_ name: String) throws -> EditorState { try decode(EditorState.self, try fixture(name)) }

/// The copy of the Mac's state, event by event (the Android app's RemoteStateTest, case for case).
struct StateTests {
    @Test func aNewMessageIsAppendedOnce() {
        var state = loaded(conv("C1", msg("M1")))
        let event = APIEvent(type: "message_appended", conversationID: id("C1"), message: msg("M2", "Hi", at: t0 + 5))
        #expect(state.apply(event).isEmpty)
        #expect(state.conversation(id("C1"))?.messages.map(\.id) == [id("M1"), id("M2")])
        #expect(state.conversation(id("C1"))?.updatedAt == t0 + 5)
        state.apply(event)
        #expect(state.conversation(id("C1"))?.messages.count == 2)
    }

    @Test func anUntitledChatIsNamedAfterItsFirstQuestion() {
        var state = loaded(conv("C1", title: Conversation.untitled))
        let text = "search for any emails from Bob from the last two days please"
        state.apply(APIEvent(type: "message_appended", conversationID: id("C1"), message: msg("M1", text, role: .user)))
        #expect(state.conversation(id("C1"))?.title == "search for any emails from Bob from the…")
        #expect(Conversation.title(from: "\n  /unread  \nmore") == "/unread")
    }

    @Test func aMessageForAnUnknownChatFetchesTheList() {
        var state = RemoteState()
        #expect(state.apply(APIEvent(type: "message_appended", conversationID: id("C9"), message: msg("M1"))) == [.refreshList])
        #expect(state.conversations.isEmpty)
    }

    @Test func aChatNotLoadedYetIsntAppendedTo() {
        var state = loaded(conv("C1"))
        state.unloaded = [id("C1")]
        state.apply(APIEvent(type: "message_appended", conversationID: id("C1"), message: msg("M1")))
        #expect(state.conversation(id("C1"))?.messages.isEmpty == true)  // fetched in full when opened
    }

    @Test func anUpdateReplacesTheMessage() {
        var state = loaded(conv("C1", msg("M1", "Summarising…")))
        state.apply(APIEvent(type: "message_updated", conversationID: id("C1"), message: msg("M1", "Done")))
        #expect(state.conversation(id("C1"))?.messages.first?.text == "Done")
    }

    @Test func typedTextStaysOverAnOlderEcho() {
        let card = Card.suggestedNote(SuggestedNoteCard(section: "People", note: "- old", source: "Re: Q4"))
        var state = loaded(conv("C1", msg("M1", card: card)))
        state.type(TypedEdit(suggestion: "- new"), on: id("M1"), in: id("C1"))
        #expect(state.conversation(id("C1"))?.messages.first?.card == .suggestedNote(SuggestedNoteCard(section: "People", note: "- new", source: "Re: Q4")))
        // The Mac's echo of the old text arrives late: what was typed still shows.
        state.apply(APIEvent(type: "message_updated", conversationID: id("C1"), message: msg("M1", card: card)))
        #expect(state.conversation(id("C1"))?.messages.first?.card == .suggestedNote(SuggestedNoteCard(section: "People", note: "- new", source: "Re: Q4")))
    }

    @Test func typedNoteEntrySplitsIntoLines() throws {
        let cards = try decode([Card].self, try fixture("other-cards.json"))
        let edited = TypedEdit(heading: "### 261106: Edited", body: "- one\n- two").applied(to: msg("M1", card: cards[4]))
        guard case .notes(let notes) = edited.card else { Issue.record("not a notes card"); return }
        #expect(notes.entry == NoteEntry(heading: "### 261106: Edited", lines: ["- one", "- two"]))
    }

    @Test func aRewriteStreamingInWinsOverTypedCRMText() throws {
        guard case .crm(var card) = try decode(Card.self, try fixture("crm-card.json")) else { Issue.record("not a CRM card"); return }
        let typed = TypedEdit(crmText: "mine")
        guard case .crm(let shown) = typed.applied(to: msg("M1", card: .crm(card))).card else { return }
        #expect(shown.text == "mine")
        card.rewriting = true
        guard case .crm(let rewriting) = typed.applied(to: msg("M1", card: .crm(card))).card else { return }
        #expect(rewriting.text == "Hi")
    }

    @Test func chatStatusAndBusy() {
        var state = loaded(conv("C1"))
        state.apply(APIEvent(type: "chat_status", conversationID: id("C1"), status: "Searching email…"))
        #expect(state.isAnswering(id("C1")))
        state.apply(APIEvent(type: "chat_status", conversationID: id("C1")))
        #expect(!state.isAnswering(id("C1")))
        state.apply(APIEvent(type: "busy", messageID: id("M1"), busy: true))
        #expect(state.busyMessages == [id("M1")])
        state.apply(APIEvent(type: "busy", messageID: id("M1"), busy: false))
        #expect(state.busyMessages.isEmpty)
    }

    @Test func storeAndConfigEvents() {
        var state = RemoteState()
        state.apply(APIEvent(type: "store_error", error: "disk full"))
        #expect(state.storeError == "disk full")
        state.apply(APIEvent(type: "store_error"))
        #expect(state.storeError == nil)
        #expect(state.apply(APIEvent(type: "config_changed")) == [.refreshInfo])
        #expect(state.apply(APIEvent(type: "conversations_changed")) == [.refreshList])
        let before = state
        state.apply(APIEvent(type: "something_new"))
        #expect(state == before)
    }

    @Test func theListKeepsLoadedMessagesAndAnEmptyLocalChat() {
        var state = loaded(conv("C1", msg("M1")), conv("NEW"))
        state.unloaded = [id("GONE")]
        state.setList([
            ConversationListItem(id: id("C2"), title: "Other", createdAt: t0, updatedAt: t0 + 60),
            ConversationListItem(id: id("C1"), title: "Renamed", createdAt: t0, updatedAt: t0 + 30),
            ConversationListItem(id: id("C1"), title: "Duplicate", createdAt: t0, updatedAt: t0),
        ])
        #expect(state.conversations.map(\.id) == [id("C2"), id("C1"), id("NEW")])
        #expect(state.conversation(id("C1"))?.title == "Renamed")
        #expect(state.conversation(id("C1"))?.messages.count == 1)
        #expect(state.unloaded == [id("C2")])
    }

    @Test func aDetailLoadsMessagesStatusAndBusy() {
        var state = loaded(conv("C1"))
        state.unloaded = [id("C1")]
        state.busyMessages = [id("M2")]
        state.setDetail(ConversationDetail(conversation: conv("C1", msg("M1"), msg("M2")), chatStatus: "Thinking…",
                                           answering: true, busyMessages: [id("M1")]))
        #expect(!state.unloaded.contains(id("C1")))
        #expect(state.busyMessages == [id("M1")])
        #expect(state.chatStatus[id("C1")] == "Thinking…")
    }

    @Test func editorsOpenUpdateAndClose() throws {
        let opened = try editor("editor-reply.json")
        var state = RemoteState()
        state.apply(APIEvent(type: "editor_opened", editor: opened))
        // Typed here while it's being written.
        state.editor(opened.id) { $0.form.subject = "Re: Q4 — mine" }
        // The body streams in; what was typed in other fields stays.
        var streaming = opened
        streaming.form.body = "Dear Bob"
        state.apply(APIEvent(type: "editor_updated", editor: streaming))
        #expect(state.editors[opened.id]?.form.body == "Dear Bob")
        #expect(state.editors[opened.id]?.form.subject == "Re: Q4 — mine")
        // The update that ends the writing carries the finished body.
        var done = opened
        done.form.body = "Dear Bob, no thanks."
        done.status = .idle
        state.apply(APIEvent(type: "editor_updated", editor: done))
        #expect(state.editors[opened.id]?.form.body == "Dear Bob, no thanks.")
        #expect(state.editors[opened.id]?.status == .idle)
        // Now the body is this device's: an update while idle doesn't overwrite it.
        state.editor(opened.id) { $0.form.body = "Mine" }
        done.status = .saving
        state.apply(APIEvent(type: "editor_updated", editor: done))
        #expect(state.editors[opened.id]?.form.body == "Mine")
        #expect(state.editors[opened.id]?.status == .saving)
        state.apply(APIEvent(type: "editor_closed", editorID: opened.id))
        #expect(state.editors.isEmpty)
    }

    @Test func anotherDevicesEditorUpdateIsIgnored() throws {
        var state = RemoteState()
        state.apply(APIEvent(type: "editor_updated", editor: try editor("editor-reply.json")))
        #expect(state.editors.isEmpty)
    }

    @Test func reconnectingFindsEditorsOpenedAndDropsOnesClosed() throws {
        let kept = try editor("editor-reply.json")
        let gone = try editor("editor-existing.json")
        var missed = gone
        missed.id = id("MISSED")
        var typed = kept
        typed.form.body = "typed here"
        var state = RemoteState()
        state.editors = [kept.id: typed, gone.id: gone]
        state.setEditors([kept, missed])
        #expect(Set(state.editors.keys) == [kept.id, missed.id])
        #expect(state.editors[kept.id]?.form.body == "typed here")  // not replaced
    }

    @Test func theIndicator() {
        #expect(Connection().indicator == .connecting)
        #expect(Connection(connected: true).indicator == .connected)
        #expect(Connection(problem: "Can't reach").indicator == .failed)
        #expect(Connection(connected: true, problem: "One request failed").indicator == .connected)
    }

    @Test func threadFolding() throws {
        guard case .thread(var thread) = try decode(ChatMessage.self, try fixture("thread-message.json")).card else { return }
        let older = EmailMessage(id: "old", from: EmailAddress(name: nil, email: "me@example.com"), to: [], cc: [],
                                 received: t0 - 3600, subject: "Q4", unread: false, attachments: [], body: "Earlier",
                                 bodyTruncated: false, bodyTotalChars: nil, quotedRemoved: false, bodyNote: nil)
        thread.messages.insert(older, at: 0)
        #expect(thread.newestFirst.map(\.id) == ["18c2a", "old"])
        #expect(thread.foldedCount == 1)
        #expect(thread.foldAllButton == .expandAll)
        #expect(!thread.canFoldAgain(older))
        thread.toggle("old")
        #expect(thread.isOpen(older))
        #expect(thread.canFoldAgain(older))
        #expect(thread.foldAllButton == .foldOlder)
        thread.side = .summary
        #expect(thread.foldAllButton == nil)
    }

    @Test func replyAllOnlyWhenItReachesSomeoneMore() throws {
        guard case .thread(var thread) = try decode(ChatMessage.self, try fixture("thread-message.json")).card else { return }
        #expect(!thread.offersReplyAll)  // just Bob and me
        thread.messages[0].cc = [EmailAddress(name: "Carol", email: "carol@example.com")]
        #expect(thread.offersReplyAll)
    }

    @Test func taskGroupsAgainstToday() throws {
        guard case .tasks(let list) = try decode([Card].self, try fixture("tasks.json"))[0] else { return }
        let groups = TaskDates.grouped(list.tasks, today: "2026-11-14")
        #expect(groups.map(\.0) == [.overdue, .upcoming, .noDate])
        #expect(groups.map { $0.1.map(\.id) } == [["t2"], ["t1"], ["t3"]])
        let utc = TimeZone(identifier: "UTC")!
        let saturday = TaskDates.date("2026-11-14", timeZone: utc)!
        #expect(TaskDates.label("2026-11-15", now: saturday, timeZone: utc) == "Tomorrow")
        #expect(TaskDates.label("2026-11-20", now: saturday, timeZone: utc) == "Fri 20 Nov")
        #expect(TaskDates.nextMonday(from: saturday, timeZone: utc) == "2026-11-16")
    }
}
