import Foundation
import Testing
@testable import FUMailKit

/// FU Mail 6.1.0's archive card: conversations, two lists, and "remember".
struct ArchiveCardTests {
    private func row(_ key: String, _ extra: String = "", archived: Bool = false) -> String {
        #"{"alreadyArchived":\#(archived),"item":{"emailKey":"\#(key)","ref":{"server":"tb","account":"work","id":1},"#
            + #""from":{"email":"\#(key)@x.example"},"subject":"S \#(key)"\#(extra)}}"#
    }
    private let targets = #","targets":[{"ref":{"server":"tb","id":1,"headerMessageID":"a@x"},"subject":"S"},"#
        + #"{"ref":{"server":"tb","id":2},"from":{"email":"b@x"},"received":"2026-11-24T08:30:00Z"}],"unread":2,"newest":{"x":1}"#

    private func card(complete: String? = #"[]"#) throws -> RepliedArchiveCard {
        let text = #"{"repliedArchive":{"_0":{"days":7,"rows":[\#(row("r1", complete == nil ? "" : targets)),\#(row("r2")),\#(row("r3", archived: true))]"#
            + (complete.map { #","complete":\#($0),"scanNote":"40 conversations: 2 replied, 2 complete""# } ?? "") + "}}}"
        guard case .repliedArchive(let card) = try decode(Card.self, text) else { throw CancellationError() }
        return card
    }
    private var full: String { "[" + row("c1", #","reason":"Bob said thanks.""# + targets) + "," + row("c2", #","reason":"Done.""#) + "]" }
    private func view(_ card: RepliedArchiveCard, busy: Bool = false) -> TriageView {
        TriageRules.view(card, busy: busy, connected: true) { _ in "Tue" }
    }

    @Test func decodesWithAndWithoutTheNewFields() throws {
        let new = try card(complete: full)
        #expect(new.rows[0].item.emailCount == 2)
        #expect(new.rows[0].item.unread == 2)
        #expect(new.rows[1].item.emailCount == 1)
        #expect(new.complete?.map(\.item.reason) == ["Bob said thanks.", "Done."])
        #expect(new.scanNote == "40 conversations: 2 replied, 2 complete")
        #expect(try json(new.rows[0].item.targets?[0].ref) == #"{"headerMessageID":"a@x","id":1,"server":"tb"}"#)
        let old = try card(complete: nil)
        #expect(old.complete == nil && old.scanNote == nil)
        #expect(old.rows.allSatisfy { $0.item.targets == nil && $0.item.reason == nil && $0.item.unread == nil })
    }

    @Test func listsCountsAndLabels() throws {
        let v = view(try card(complete: full))
        #expect(v.title == "Archive (last 7d)")
        #expect(v.sections.map(\.title) == ["You replied last", "Complete"])
        #expect(v.sections.map { $0.rows.count } == [3, 2])
        #expect(v.sections.map { $0.all?.label } == ["Archive all (2)", "Archive all (2)"])
        #expect(v.sections[0].rows[0].buttons.map(\.label) == ["Archive 2", "Keep"])
        #expect(v.sections[0].rows[1].buttons.map(\.label) == ["Archive", "Keep"])
        #expect(v.sections[0].rows[0].details == ["work", "2 emails in Inbox", "2 unread", "you replied last"])
        #expect(v.sections[0].rows[1].details == ["work", "you replied last"])
        #expect(v.sections[1].rows[0].details == ["work", "2 emails in Inbox", "2 unread", "Bob said thanks."])
        #expect(v.sections[0].rows[2].mark == "Already archived")
        #expect(v.scanNote == "40 conversations: 2 replied, 2 complete")
        let empty = view(RepliedArchiveCard(complete: []))
        #expect(empty.sections.map(\.emptyText) == ["None.", "None judged complete."])
        #expect(empty.sections.allSatisfy { $0.all == nil })
    }

    @Test func questionsSayWhatHappens() throws {
        let v = view(try card(complete: full))
        let all = try #require(v.sections[0].all).confirmation
        #expect(all.title == "Archive 2 conversations?")
        #expect(all.text == "3 Inbox emails will be moved to Archive. Sent mail stays where it is. A conversation with a new message is left alone.")
        #expect(try #require(v.sections[1].all).confirmation.text.hasPrefix("3 Inbox emails"))
        let one = v.sections[0].rows[0].buttons[0].confirmation
        #expect(one.title == "Archive this conversation?")
        #expect(one.text.contains("2 Inbox emails will be moved to Archive."))
    }

    @Test func eachArchiveAllSendsItsOwnActionForItsOwnList() throws {
        let v = view(try card(complete: full))
        #expect(v.sections[0].all?.action.json.serialized() == #"{"action":"archive_replied_all"}"#)
        #expect(v.sections[1].all?.action.json.serialized() == #"{"action":"archive_complete_all"}"#)
        #expect(CardAction.archiveCompleteAll.isTriage)
        // An old card has no Complete list to act on.
        let old = view(try card(complete: nil))
        #expect(old.sections[1].rows.isEmpty && old.sections[1].all == nil)
        #expect(!old.rows.flatMap { $0.buttons + $0.menu }.contains { $0.action == .archiveCompleteAll })
    }

    @Test func rememberOnlyWhenChosen() throws {
        let v = view(try card(complete: full))
        let row = v.sections[1].rows[0]
        #expect(row.buttons.map { $0.action.json.serialized() }
                == [#"{"action":"archive_replied_one","email_key":"c1"}"#, #"{"action":"archive_replied_keep","email_key":"c1"}"#])
        #expect(row.menu.map(\.label) == ["Archive & remember", "Keep & remember"])
        #expect(row.menu.map { $0.action.json.serialized() }
                == [#"{"action":"archive_replied_one","email_key":"c1","remember":true}"#,
                    #"{"action":"archive_replied_keep","email_key":"c1","remember":true}"#])
        #expect(row.menu.allSatisfy { $0.confirmation.text.contains("## Archive") })
    }

    @Test func aListsQuestionClosesOnlyWhenThatListChanges() throws {
        let card = try card(complete: full)
        let v = view(card)
        let replied = try #require(v.sections[0].all).confirmation
        let complete = try #require(v.sections[1].all).confirmation
        let row = v.sections[1].rows[1].buttons[0].confirmation
        #expect(replied.holds(.repliedArchive(card), busy: false, connected: true))
        var changed = card
        changed.complete?.removeFirst()
        #expect(replied.holds(.repliedArchive(changed), busy: false, connected: true))  // the other list
        #expect(!complete.holds(.repliedArchive(changed), busy: false, connected: true))
        #expect(row.holds(.repliedArchive(changed), busy: false, connected: true))  // its row is still there
        changed = card
        changed.rows.removeLast()
        #expect(!replied.holds(.repliedArchive(changed), busy: false, connected: true))
        #expect(complete.holds(.repliedArchive(changed), busy: false, connected: true))
        #expect(!complete.holds(.repliedArchive(card), busy: true, connected: true))
        #expect(!complete.holds(.repliedArchive(card), busy: false, connected: false))
        #expect(view(card, busy: true).rows.flatMap { $0.buttons + $0.menu }.allSatisfy { !$0.enabled })
    }
}
