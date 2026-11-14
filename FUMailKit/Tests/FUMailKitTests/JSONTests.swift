import Foundation
import Testing
@testable import FUMailKit

/// The Mac's JSON reads into the copied types, and what's sent back is what the Mac reads.
struct JSONTests {
    @Test func theThreadMessageFromTheAPIDocs() throws {
        let message = try decode(ChatMessage.self, try fixture("thread-message.json"))
        #expect(message.role == .assistant)
        #expect(message.createdAt == ISO8601DateFormatter().date(from: "2026-11-13T08:11:55Z"))
        guard case .thread(let card) = message.card else { Issue.record("not a thread: \(String(describing: message.card))"); return }
        #expect(card.ref.idString == "18c2a")
        #expect(card.mailbox == "me@example.com")
        #expect(card.side == .original)
        #expect(card.unfolded == nil)
        let email = try #require(card.messages.first)
        #expect(email.to.first?.email == "me@example.com")
        #expect(email.to.first?.name == nil)
        #expect(email.attachments == ["a.pdf"])
        #expect(email.quotedRemoved)
        #expect(card.summary?.state == .done)
        #expect(card.summary?.by == "gemini · flash")
        #expect(card.archived == nil)
    }

    @Test func aListCardWithStringAndNumberIDs() throws {
        guard case .emailList(let card) = try decode(Card.self, try fixture("list-card.json")) else { Issue.record("not a list"); return }
        #expect(card.kind == .unread)
        #expect(card.title == "Unread")
        #expect(card.items[0].ref.idString == "18c2a")
        #expect(card.items[1].ref.idString == "40213")
        #expect(card.items[1].ref.account == nil)
        #expect(card.items[1].snippet == nil)
        #expect(card.more == nil)
    }

    @Test func refIDsGoBackExactlyAsReceived() throws {
        guard case .emailList(let card) = try decode(Card.self, try fixture("list-card.json")) else { Issue.record("not a list"); return }
        #expect(try json(card.items[1].ref) == #"{"id":40213,"server":"macia"}"#)  // a number, and no "account"
        #expect(try json(card.items[0].ref) == #"{"account":"fanda","id":"18c2a","server":"gmail-mcp"}"#)
    }

    @Test func archiveListsAndArchivedThreads() throws {
        guard case .emailList(var card) = try decode(Card.self, try fixture("archive.json")) else { Issue.record("not a list"); return }
        #expect(card.kind == .archive("renewal · with acme.com"))
        #expect(card.title == "Archive: renewal · with acme.com")
        #expect(card.emptyText == "Nothing in the archive matched.")
        #expect(card.more?.total == 22)
        #expect(card.more?.tokens == ["archive": "15"])
        #expect(card.more?.search.person == "acme.com")
        #expect(card.remainingCount == 20)  // 22 matched, 2 shown
        card.more?.total = 1
        #expect(card.remainingCount == 0)  // never below 0
        card.more?.total = nil
        #expect(card.remainingCount == nil)  // just "Show more"
        card.kind = .archive("")
        #expect(card.title == "Archive")
        #expect(card.emptyText == "The archive is empty.")

        let message = try fixture("thread-message.json").replacingOccurrences(of: #""fullText":false"#,
                                                                             with: #""fullText":false,"archived":true"#)
        guard case .thread(let thread) = try decode(ChatMessage.self, message).card else { Issue.record("not a thread"); return }
        #expect(thread.archived == true)
        #expect(!thread.offersReplyAll)
        #expect(CardAction.archiveMore.json.serialized() == #"{"action":"archive_more"}"#)
    }

    @Test func theCRMCardFromTheAPIDocs() throws {
        guard case .crm(let card) = try decode(Card.self, try fixture("crm-card.json")) else { Issue.record("not a CRM card"); return }
        #expect(card.stage == .choosing)
        #expect(card.noteHint == "UOB")
        #expect(card.candidates.first?.score == 2)
        #expect(card.chosen == nil)
        #expect(card.syncStatus == nil)
    }

    @Test func everyOtherCard() throws {
        let cards = try decode([Card].self, try fixture("other-cards.json"))
        guard case .draftList(let drafts) = cards[0], case .draft(let draft) = cards[1], case .events(let week) = cards[2],
              case .events(let search) = cards[3], case .notes(let notes) = cards[4], case .suggestedNote(let suggestion) = cards[5]
        else { Issue.record("wrong kinds: \(cards)"); return }
        #expect(drafts.items.first?.draftID == "r-1")
        #expect(drafts.problems == ["macia: can't save drafts"])
        #expect(draft.isReply)
        #expect(draft.body == "Thanks Bob")
        #expect(week.kind == .days(7))
        #expect(week.title == "Next 7 days")
        #expect(week.duplicatesRemoved == 1)
        #expect(week.events.first?.videoLink == "https://meet.google.com/x")
        #expect(search.kind == .search("bob", days: 30))
        #expect(search.emptyText == "No events matched.")
        #expect(notes.stage == .preview)
        #expect(notes.entry.heading == "### 261106: Q4 Approval")
        #expect(notes.duplicate?.exact == false)
        #expect(notes.choiceKeys == ["thread:t-18c2a", "domain:example.com"])
        #expect(suggestion.section == "People")
        #expect(cards[6] == .unsupported("someFutureCard"))
    }

    @Test func theNoteCard() throws {
        let cards = try decode([Card].self, try fixture("note-view.json"))
        guard case .noteView(var showing) = cards[0], case .noteView(let choosing) = cards[1] else {
            Issue.record("wrong kinds: \(cards)")
            return
        }
        #expect(showing.stage == .showing)
        #expect(showing.only == .crm)
        #expect(showing.shows(.crm))
        #expect(!showing.shows(.summary))
        #expect(showing.kind == "project")
        #expect(showing.crm.count == 6)
        #expect(showing.shown(.crm, showing.crm).count == 5)  // the newest 5
        #expect(showing.readAt == ISO8601DateFormatter().date(from: "2026-11-13T10:05:00Z"))
        #expect(showing.catchUp?.state == .done)
        #expect(showing.canPostCRM)
        showing.expanded = [.crm]
        #expect(showing.shown(.crm, showing.crm).count == 6)

        #expect(choosing.stage == .choosing)
        #expect(choosing.candidates.map(\.title) == ["NTT Data", "NTT Migration"])
        #expect(choosing.only == nil)  // left out: all three sections
        #expect(choosing.catchUp == nil)
        #expect(choosing.readAt == nil)
        // A section this version doesn't know doesn't break the card.
        #expect(choosing.expanded == [.crm, .unknown])
    }

    @Test func aCRMCardCanStartAtItsPreview() throws {
        let cards = try decode([Card].self, try fixture("note-view.json"))
        guard case .crm(let crm) = cards[2] else { Issue.record("not a CRM card"); return }
        #expect(crm.stage == .preview)
        #expect(crm.text == "")
        #expect(crm.chosen?.title == "A")
        #expect(crm.entry == ["### 261113: fyoo"])
        #expect(crm.candidates.isEmpty)
    }

    @Test func tasksCards() throws {
        let cards = try decode([Card].self, try fixture("tasks.json"))
        guard case .tasks(let list) = cards[0], case .taskDraft(let draft) = cards[1], case .taskChange(let move) = cards[2],
              case .taskChange(let undate) = cards[3], case .taskChange(let done) = cards[4] else {
            Issue.record("wrong kinds: \(cards)")
            return
        }
        #expect(list.list == "Urgent")
        #expect(list.tasks.map(\.id) == ["t1", "t2", "t3"])
        #expect(list.tasks[1].completed)
        #expect(list.tasks[2].dueDate == nil)
        #expect(list.busy == ["t2"])
        #expect(draft.titleBy == "summary · gemini")
        #expect(draft.stage == .editing)
        #expect(move.change == .reschedule(dueDate: "2026-11-23"))
        #expect(undate.change == .reschedule(dueDate: nil))
        #expect(undate.stage == .done)
        #expect(done.change == .complete)
        #expect(done.stage == .cancelled)
    }

    @Test func aCardThatCantBeReadDoesntLoseTheMessage() throws {
        let message = try decode(ChatMessage.self, #"""
            {"id":"\#(id("M1"))","role":"assistant","text":"Here","createdAt":"2026-11-13T08:11:55Z","card":{"thread":{"_0":{"subject":"no ref"}}}}
            """#)
        #expect(message.text == "Here")
        #expect(message.card == .unsupported("thread"))
    }

    @Test func unknownFieldsAndRolesDontFail() throws {
        let message = try decode(ChatMessage.self, #"""
            {"id":"\#(id("M1"))","role":"narrator","text":"x","createdAt":"2026-11-13T08:11:55Z","somethingNew":true}
            """#)
        #expect(message.role == .system)
    }

    @Test func editorsInBothModes() throws {
        let reply = try decode(EditorState.self, try fixture("editor-reply.json"))
        #expect(reply.status == .writing("draft · gemini-3.5-flash-lite"))
        guard case .reply(let context, let thread) = reply.mode else { Issue.record("not a reply"); return }
        #expect(context.mailbox == "me@example.com")
        #expect(thread.subject == "Q4")
        #expect(reply.signature == "Frank")

        let existing = try decode(EditorState.self, try fixture("editor-existing.json"))
        #expect(existing.status == .idle)
        guard case .existing(let draft, let messageID) = existing.mode else { Issue.record("not a draft"); return }
        #expect(messageID == id("M2"))
        #expect(draft.draftID == "r-1")
        #expect(existing.signature == nil)
    }

    @Test func editorStatusesRoundTrip() throws {
        for status in [EditorStatus.idle, .writing("a · b"), .saving, .failed("why")] {
            #expect(try decode(EditorStatus.self, try json(status)) == status)
        }
        #expect(try json(EditorStatus.saving) == #"{"saving":{}}"#)
        #expect(try json(EditorStatus.failed("why")) == #"{"failed":{"_0":"why"}}"#)
    }

    @Test func theDraftFormIsSentWithEveryField() throws {
        #expect(try json(DraftForm(subject: "Re: Q4")) == #"{"bcc":"","body":"","cc":"","replyAll":false,"subject":"Re: Q4","to":""}"#)
    }

    @Test func infoAndProviderLine() throws {
        let info = try decode(APIInfo.self, try fixture("info.json"))
        #expect(info.device == "phone")
        #expect(info.providerLine?.entries.map(\.key) == ["chat", "summary"])
        #expect(info.providerLine?.entries[1].remote == true)
        #expect(info.configError == nil)
        #expect(info.crmConfigured == true)
        #expect(info.crmSection == nil)
        // An older or newer Mac sends less.
        let slim = try decode(APIInfo.self, #"{"version":"2.3.1","crmSection":"CRM","crmConfigured":true}"#)
        #expect(slim.crmSection == "CRM")
        #expect(slim.device == nil)
    }

    @Test func commands() throws {
        let commands = try decode([Command].self, #"""
            [{"name":"/unread","args":"[n]","summary":"newest unread email"},{"name":"/today","args":"","summary":"today's events"},{"name":"/new"}]
            """#)
        #expect(commands[0].args == "[n]")
        #expect(commands[1].args == "")
        #expect(commands[2].summary == "")
    }

    @Test func slimNoteListsParseAndFilterByAnyName() throws {
        let notes = try decode([NoteFile].self, #"""
            [{"path":"ignivo/project/UOB.md","title":"UOB","related":["United Overseas Bank"],"stakeholders":["Teo Kim Beng"],"summary":"","entries":[],"firstTag":"project"}]
            """#)
        let uob = try #require(notes.first)
        #expect(uob.matches("uob"))
        #expect(uob.matches("overseas"))
        #expect(uob.matches("kim beng"))
        #expect(uob.matches(" "))
        #expect(!uob.matches("nttdata"))
        #expect(uob.kind == "project")
        #expect(uob.asCRMCandidate.reason == "chosen from the list")
    }

    @Test func eventsWithAndWithoutFields() throws {
        let closed = try decode(APIEvent.self, #"{"type":"editor_closed","editorID":"\#(id("E1"))"}"#)
        #expect(closed.editorID == id("E1"))
        let done = try decode(APIEvent.self, #"{"type":"chat_status","conversationID":"\#(id("C1"))"}"#)
        #expect(done.status == nil)
        let appended = try decode(APIEvent.self, #"{"type":"message_appended","conversationID":"\#(id("C1"))","message":\#(try fixture("thread-message.json"))}"#)
        guard case .thread = appended.message?.card else { Issue.record("no thread card"); return }
    }

    @Test func cardActionsMatchTheMacsJSON() {
        #expect(CardAction.toggleFold(emailID: "18c2a").json.serialized() == #"{"action":"toggle_fold","email_id":"18c2a"}"#)
        #expect(CardAction.setSide(.summary).json.serialized() == #"{"action":"set_side","side":"summary"}"#)
        #expect(CardAction.reply(instructions: "", blank: false, replyAll: true).json.serialized()
                == #"{"action":"reply","blank":false,"instructions":"","reply_all":true}"#)
        #expect(CardAction.insertNote(replace: true).json.serialized() == #"{"action":"insert_note","replace":true}"#)
        #expect(CardAction.editNoteEntry(heading: "### H", body: "- a\n- b").json.serialized()
                == ####"{"action":"edit_note_entry","body":"- a\n- b","heading":"### H"}"####)
        let candidate = NoteCandidate(path: "p/A.md", title: "A", reason: "chosen from the list", score: 0)
        #expect(CardAction.crmChoose(candidate).json["candidate"]?.serialized()
                == #"{"path":"p/A.md","reason":"chosen from the list","score":0,"title":"A"}"#)
        #expect(CardAction.crmRewrite(text: "t", instructions: "shorter").json.serialized()
                == #"{"action":"crm_rewrite","instructions":"shorter","text":"t"}"#)
        #expect(CardAction.noteViewExpand(.correspondence).json.serialized() == #"{"action":"note_view_expand","section":"correspondence"}"#)
        #expect(CardAction.taskReschedule(taskID: "t1", dueDate: nil).json.serialized()
                == #"{"action":"task_reschedule","due_date":"","task_id":"t1"}"#)
    }

    @Test func datesAreWrittenWithoutFractions() throws {
        let message = ChatMessage(id: id("M1"), role: .user, createdAt: Date(timeIntervalSince1970: 1_799_999_999.5))
        #expect(try json(message).contains(#""createdAt":"2027-01-15T07:59:59Z""#))
    }
}
