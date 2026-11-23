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
        #expect(CardAction.deleteEmail.json.serialized() == #"{"action":"delete_email"}"#)
        #expect(CardAction.refreshDraft.json.serialized() == #"{"action":"refresh_draft"}"#)
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

    @Test func aMessageThatCantBeReadDoesntLoseTheConversation() throws {
        let good = try fixture("thread-message.json")
        let bad = #"{"id":"not-a-uuid","role":"user","text":"x","createdAt":"2026-11-13T08:11:55Z"}"#
        let conversation = try decode(Conversation.self, #"""
            {"id":"\#(id("C1"))","title":"Unread","createdAt":"2026-11-13T08:00:00Z","updatedAt":"2026-11-13T08:00:00Z","messages":[\#(bad),\#(good)]}
            """#)
        #expect(conversation.messages.map(\.id) == [id("M1")])
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

    @Test func aSearchHitSaysWhichMessageMatched() throws {
        let base = #""conversationID":"5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A00","title":"T","updatedAt":"2026-11-16T09:00:00Z","snippet":"«Bob»""#
        let hit = try decode(SearchHit.self, "{\(base),\"messageID\":\"5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A01\"}")
        #expect(hit.messageID == UUID(uuidString: "5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A01"))
        #expect(try decode(SearchHit.self, "{\(base)}").messageID == nil)  // a Mac before 3.3.0
    }

    @Test func aDraftCardSaysWhenItsDraftIsGone() throws {
        let fields = #""server":"gmail-mcp","draftID":"r-1","to":[],"cc":[],"bcc":[],"subject":"S","body":"B","isReply":false,"link":"https://mail.google.com/d""#
        let there = try decode(DraftCard.self, "{\(fields)}")
        #expect(there.gone == nil && there.hasGmailLink)
        #expect(try decode(DraftCard.self, "{\(fields),\"gone\":true}").gone == true)
        #expect(!(try json(there)).contains("gone"))  // left out unless set
        #expect(there.warning == nil)  // a Mac before 3.7.0, or nothing to warn about
        let warned = try decode(DraftCard.self, "{\(fields),\"warning\":\"The new body replaced the draft's formatting.\"}")
        #expect(warned.warning == "The new body replaced the draft's formatting.")
    }

    @Test func aNowCardIsTitledWithItsTimeZone() throws {
        func card(_ kind: String, _ extra: String = "") throws -> EventListCard {
            try decode(EventListCard.self, #"{"kind":\#(kind),"events":[],"problems":[],"duplicatesRemoved":0\#(extra)}"#)
        }
        let today = #"{"days":{"_0":1}}"#
        let now = try card(today, #","from":"2026-11-18T09:00:00Z","timeZone":"Europe/London""#)
        #expect(now.title == "Now (Europe/London)")
        #expect(now.emptyText == "Nothing more on today.")
        #expect(now.from != nil)
        let zoneless = try card(today, #","from":"2026-11-18T09:00:00Z""#)
        #expect(zoneless.title == "Now")
        #expect(zoneless.emptyText == "Nothing more on today.")
        // Without "from": as before.
        let plain = try card(today)
        #expect(plain.title == "Today" && plain.emptyText == "Nothing on today." && plain.timeZone == nil)
        let week = try card(#"{"days":{"_0":7}}"#)
        #expect(week.title == "Next 7 days" && week.emptyText == "Nothing on.")
        let search = try card(#"{"search":{"_0":"bob","days":30}}"#)
        #expect(search.title == "Events: bob (next 30 days)" && search.emptyText == "No events matched.")
    }

    // MARK: Memos (FU Mail 4.5.0)

    @Test func aMemoOpensInMemosAndAVaultFileInObsidian() {
        #expect(Notes.isMemo("memos/abc123"))
        #expect(!Notes.isMemo("ignivo/project/UOB.md"))
        #expect(!Notes.isMemo("memos/old.md"))  // a vault folder that happens to be called memos
        #expect(Notes.memosURL(path: "memos/abc123", memosURL: "https://memo.cooltym.net")?.absoluteString
                == "https://memo.cooltym.net/memos/abc123")
        #expect(Notes.memosURL(path: "memos/abc123", memosURL: "https://memo.cooltym.net/")?.absoluteString
                == "https://memo.cooltym.net/memos/abc123")
        #expect(Notes.memosURL(path: "memos/abc123", memosURL: "") == nil)
        #expect(Notes.memosURL(path: "ignivo/project/UOB.md", memosURL: "https://memo.cooltym.net") == nil)
        // Vault files: the obsidian:// link as before.
        #expect(Notes.obsidianURL(path: "ignivo/project/UOB.md", vault: "Work")?.absoluteString
                == "obsidian://open?vault=Work&file=ignivo/project/UOB")
    }

    @Test func theMacSaysWhereMemosIs() throws {
        let info = try fixture("info.json")
        #expect(try decode(APIInfo.self, info).memosURL == nil)  // a Mac before 4.5.0, or no Memos
        let withMemos = info.replacingOccurrences(of: "{", with: #"{"memosURL":"https://memo.cooltym.net","#,
                                                  options: [], range: info.range(of: "{"))
        #expect(try decode(APIInfo.self, withMemos).memosURL == "https://memo.cooltym.net")
    }

    @Test func anEntrySaysWhetherItWentToMemosOrTheVault() throws {
        #expect(Notes.withPlace("Added to UOB", savedTo: "Memos") == "Added to UOB (Memos)")
        #expect(Notes.posted(to: "UOB", section: "CRM", savedTo: "Memos") == "Posted to UOB (## CRM, Memos)")
        #expect(Notes.posted(to: "UOB", section: "CRM", savedTo: "vault") == "Posted to UOB (## CRM, vault)")
        #expect(Notes.posted(to: "UOB", section: "CRM", savedTo: nil) == "Posted to UOB (## CRM)")
        #expect(Notes.withPlace("Added to UOB", savedTo: nil) == "Added to UOB")
        let notice = "Memos can't be reached (timed out), so it went into the vault."

        let crm = try fixture("crm-card.json")
        guard case .crm(let plain) = try decode(Card.self, crm) else { Issue.record("not a CRM card"); return }
        #expect(plain.savedTo == nil && plain.notice == nil)
        let fallback = crm.replacingOccurrences(of: #"{"crm":{"_0":{"#, with: #"{"crm":{"_0":{"savedTo":"vault","notice":"\#(notice)","#)
        guard case .crm(let card) = try decode(Card.self, fallback) else { Issue.record("not a CRM card"); return }
        #expect(card.savedTo == "vault" && card.notice == notice)

        var cards = try #require(try JSONSerialization.jsonObject(with: Data(fixture("other-cards.json").utf8)) as? [[String: Any]])
        let index = try #require(cards.firstIndex { $0["notes"] != nil })
        guard case .notes(let before) = try decode(Card.self, String(decoding: JSONSerialization.data(withJSONObject: cards[index]), as: UTF8.self))
        else { Issue.record("not a notes card"); return }
        #expect(before.savedTo == nil && before.notice == nil)
        var notes = try #require(cards[index]["notes"] as? [String: Any])
        var inner = try #require(notes["_0"] as? [String: Any])
        inner["savedTo"] = "Memos"
        notes["_0"] = inner
        cards[index] = ["notes": notes]
        guard case .notes(let saved) = try decode(Card.self, String(decoding: JSONSerialization.data(withJSONObject: cards[index]), as: UTF8.self))
        else { Issue.record("not a notes card"); return }
        #expect(saved.savedTo == "Memos" && saved.notice == nil)
    }

    @Test func aNoticeCanComeBeforeAnythingIsWritten() throws {
        // Memos couldn't be reached while choosing: the notes listed came from the vault.
        var cards = try #require(try JSONSerialization.jsonObject(with: Data(fixture("other-cards.json").utf8)) as? [[String: Any]])
        let index = try #require(cards.firstIndex { $0["notes"] != nil })
        var notes = try #require(cards[index]["notes"] as? [String: Any])
        var inner = try #require(notes["_0"] as? [String: Any])
        inner["stage"] = "choosing"
        inner["notice"] = "Memos can't be reached: these notes are from the vault."
        inner.removeValue(forKey: "savedTo")
        notes["_0"] = inner
        guard case .notes(let card) = try decode(Card.self, String(decoding: JSONSerialization.data(withJSONObject: ["notes": notes]), as: UTF8.self))
        else { Issue.record("not a notes card"); return }
        #expect(card.stage == .choosing)
        #expect(card.notice == "Memos can't be reached: these notes are from the vault.")
        #expect(card.savedTo == nil)
    }

    @Test func aThreadCardSaysWhetherItCanBeDeleted() throws {
        let message = try fixture("thread-message.json")
        let plain = try decode(ChatMessage.self, message)
        guard case .thread(let before) = plain.card else { Issue.record("not a thread"); return }
        #expect(before.canDelete == nil && before.deleted == nil)
        let deletable = message.replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"canDelete":true,"#)
        guard case .thread(let card) = try decode(ChatMessage.self, deletable).card else { Issue.record("not a thread"); return }
        #expect(card.canDelete == true && card.deleted == nil)
        let gone = message.replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"deleted":true,"#)
        guard case .thread(let trashed) = try decode(ChatMessage.self, gone).card else { Issue.record("not a thread"); return }
        #expect(trashed.deleted == true && trashed.canDelete == nil)
    }

    @Test func aThreadCardSupportsSanitizedHTML() throws {
        let base = try fixture("thread-message.json")
        guard case .thread(let plain) = try decode(ChatMessage.self, base).card else { Issue.record("not a thread"); return }
        #expect(plain.canShowHTML == nil && plain.showingHTML == nil)
        #expect(plain.messages.first?.bodyHTML == nil)
        #expect(plain.headerTabs == [.original, .summary])
        #expect(plain.activeHeaderTab == .original)

        let htmlMessage = base
            .replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"canShowHTML":true,"showingHTML":true,"#)
            .replacingOccurrences(of: #""body":"Hi""#, with: #""body":"Hi","bodyHTML":"<p>Hi <a href=\"https://example.com\">link</a></p>""#)
        guard case .thread(var htmlCard) = try decode(ChatMessage.self, htmlMessage).card else { Issue.record("not a thread"); return }
        #expect(htmlCard.canShowHTML == true)
        #expect(htmlCard.showingHTML == true)
        #expect(htmlCard.messages.first?.bodyHTML == #"<p>Hi <a href="https://example.com">link</a></p>"#)
        #expect(htmlCard.headerTabs == [.original, .html, .summary])
        #expect(htmlCard.activeHeaderTab == .html)

        htmlCard.showingHTML = false
        #expect(htmlCard.activeHeaderTab == .original)
        htmlCard.side = .summary
        #expect(htmlCard.headerTabs == [.original, .html, .summary])
        #expect(htmlCard.activeHeaderTab == .summary)

        htmlCard.side = .original
        htmlCard.showingHTML = true
        htmlCard.archived = true
        #expect(htmlCard.headerTabs == [.original, .summary])
        #expect(htmlCard.activeHeaderTab == .original)
        htmlCard.archived = nil
        htmlCard.deleted = true
        #expect(htmlCard.headerTabs == [.original, .summary])
        #expect(htmlCard.activeHeaderTab == .original)

        #expect(CardAction.showHTML(on: true).json.serialized() == #"{"action":"show_html","on":true}"#)
        #expect(CardAction.showHTML(on: false).json.serialized() == #"{"action":"show_html","on":false}"#)
    }

    @Test func aThreadCardSupportsDownloadingAttachments() throws {
        let base = try fixture("thread-message.json")
        guard case .thread(let plain) = try decode(ChatMessage.self, base).card else { Issue.record("not a thread"); return }
        #expect(plain.canDownloadAttachments == nil)
        #expect(plain.messages.first?.attachmentItems == nil)
        #expect(!plain.offersAttachmentDownload)

        let withItems = base
            .replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"canDownloadAttachments":true,"#)
            .replacingOccurrences(of: #""attachments":["a.pdf"]"#,
                                  with: #""attachments":["a.pdf"],"attachmentItems":[{"filename":"a.pdf","attachmentID":"att-1","mimeType":"application/pdf","sizeBytes":2048}]"#)
        guard case .thread(var card) = try decode(ChatMessage.self, withItems).card else { Issue.record("not a thread"); return }
        #expect(card.canDownloadAttachments == true)
        #expect(card.offersAttachmentDownload)
        let item = try #require(card.messages.first?.attachmentItems?.first)
        #expect(item == EmailAttachment(filename: "a.pdf", attachmentID: "att-1", mimeType: "application/pdf", sizeBytes: 2048))

        card.archived = true
        #expect(!card.offersAttachmentDownload)
        card.archived = nil
        card.deleted = true
        #expect(!card.offersAttachmentDownload)

        #expect(CardAction.downloadAttachment(emailID: "18c2a", attachmentID: "att-1", filename: "a.pdf").json.serialized()
                == #"{"action":"download_attachment","attachment_id":"att-1","email_id":"18c2a","filename":"a.pdf"}"#)
        #expect(CardAction.downloadAttachment(emailID: "18c2a", attachmentID: nil, filename: "a.pdf").json.serialized()
                == #"{"action":"download_attachment","attachment_id":null,"email_id":"18c2a","filename":"a.pdf"}"#)
    }

    @Test func composeModeAndContactsAutocomplete() throws {
        let composeJSON = """
        {
          "id":"9F1C2B3A-0000-4000-8000-000000000003",
          "conversationID":"5A277C52-1D0B-4A43-9C9E-2D5B8F1E0A00",
          "title":"New email",
          "isReply":false,
          "server":"gmail-mcp",
          "canSave":true,
          "form":{"to":"","cc":"","bcc":"","subject":"","body":"","replyAll":false},
          "instructions":"",
          "status":{"idle":{}},
          "mode":{"compose":{
            "accounts":[{"server":"gmail-mcp","account":"work","email":"me@work.com"},{"server":"macia","account":null,"email":"home@me.com"}],
            "selected":{"server":"gmail-mcp","account":"work","email":"me@work.com"}
          }}
        }
        """
        let editor = try decode(EditorState.self, composeJSON)
        #expect(editor.isCompose)
        #expect(editor.supportsWrite)
        guard case .compose(let accounts, let selected) = editor.mode else { Issue.record("not compose"); return }
        #expect(accounts.count == 2)
        #expect(accounts[0].display == "work (me@work.com)")
        #expect(accounts[1].display == "home@me.com")
        #expect(selected == accounts[0])

        let contacts = try decode([ContactEntry].self, #"[{"name":"Alice Smith","email":"alice@example.com"},{"name":"Bob Jones","email":"bob@alice.org"},{"name":null,"email":"carol@example.com"}]"#)
        #expect(ContactEntry.suggestions(for: "al", from: contacts).map(\.email) == ["alice@example.com", "bob@alice.org"])
        #expect(ContactEntry.suggestions(for: "Alice <alice@example.com>, ca", from: contacts).map(\.email) == ["carol@example.com"])
        #expect(ContactEntry.applying(contacts[0], to: "al") == "Alice Smith <alice@example.com>, ")
        #expect(ContactEntry.applying(contacts[2], to: "Alice Smith <alice@example.com>, ca") == "Alice Smith <alice@example.com>, carol@example.com, ")
    }

    @Test func aThreadCardSaysWhetherItCanBeArchived() throws {
        let base = try fixture("thread-message.json")
        guard case .thread(let plain) = try decode(ChatMessage.self, base).card else { Issue.record("not a thread"); return }
        #expect(plain.canArchive == nil && plain.movedToArchive == nil)
        #expect(!plain.offersArchive)

        let archivable = base.replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"canArchive":true,"#)
        guard case .thread(var card) = try decode(ChatMessage.self, archivable).card else { Issue.record("not a thread"); return }
        #expect(card.canArchive == true && card.movedToArchive == nil)
        #expect(card.offersArchive)

        card.archived = true
        #expect(!card.offersArchive)
        card.archived = nil
        card.deleted = true
        #expect(!card.offersArchive)
        card.deleted = nil
        card.movedToArchive = true
        #expect(!card.offersArchive)

        let moved = base.replacingOccurrences(of: #""card":{"thread":{"_0":{"#, with: #""card":{"thread":{"_0":{"movedToArchive":true,"#)
        guard case .thread(let done) = try decode(ChatMessage.self, moved).card else { Issue.record("not a thread"); return }
        #expect(done.movedToArchive == true && done.canArchive == nil)
        #expect(!done.offersArchive)

        #expect(CardAction.archiveEmail.json.serialized() == #"{"action":"archive_email"}"#)
    }
}
