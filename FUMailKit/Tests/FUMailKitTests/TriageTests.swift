import Foundation
import Testing
@testable import FUMailKit

/// The triage review cards: their JSON, what they offer, and their confirmations (the Android app's
/// TriageTest, case for case).
struct TriageTests {
    private let cards: [Card]
    private let spam: SpamCard
    private let clean: CleanCard
    private let replied: RepliedArchiveCard

    init() throws {
        cards = try decode([Card].self, fixture("triage-cards.json"))
        guard case .spam(let spam) = cards[0], case .clean(let clean) = cards[1], case .repliedArchive(let replied) = cards[2]
        else { throw RemoteProblem(.badResponse, "the triage cards weren't read: \(cards)") }
        (self.spam, self.clean, self.replied) = (spam, clean, replied)
    }

    private func card(_ text: String) throws -> Card { try decode(Card.self, text) }
    private func date(_ text: String) throws -> Date { try Date(text, strategy: .iso8601) }

    private func view(_ card: SpamCard, busy: Bool = false, connected: Bool = true) -> TriageView {
        TriageRules.view(card, busy: busy, connected: connected)
    }
    private func view(_ card: CleanCard, busy: Bool = false, connected: Bool = true) -> TriageView {
        TriageRules.view(card, busy: busy, connected: connected)
    }
    private func view(_ card: RepliedArchiveCard, busy: Bool = false, connected: Bool = true) -> TriageView {
        TriageRules.view(card, busy: busy, connected: connected) { "on \($0.ISO8601Format().prefix(10))" }
    }

    private func labels(_ view: TriageView, _ row: Int) -> [[String]] {
        [view.rows[row].buttons.map(\.label), view.rows[row].menu.map(\.label)]
    }
    private func everyButton(_ view: TriageView) -> [TriageButton] {
        view.rows.flatMap { $0.buttons + $0.menu } + [view.all].compactMap { $0 }
    }

    // MARK: JSON

    @Test func theSpamCard() throws {
        #expect(spam.rows.count == 4)
        #expect(spam.statusNote == "1 already deleted outside FU Mail (removed from queue).")
        let first = spam.rows[0].item
        #expect(first.emailKey == "gmail-mcp|fanda|18c2a")
        #expect(first.from == EmailAddress(name: "Acme Deals", email: "deals@acme.example"))
        #expect(try first.received == date("2026-11-24T08:30:00Z"))
        #expect(try first.caughtAt == date("2026-11-24T09:00:00Z"))
        #expect(first.canDelete)
        #expect(!first.fromSpamList)
        #expect(spam.rows[1].item.fromSpamList)
        #expect(spam.rows[2].alreadyDeleted)
        #expect(spam.rows[3].item.from == nil)
        #expect(spam.rows[3].item.received == nil)
    }

    @Test func theCleanCardAllowsOtherKinds() {
        #expect(clean.rows.map(\.item.kind) == ["calendarResponse", "deliveryNotice"])
        #expect(clean.statusNote == nil)
    }

    @Test func theRepliedCard() throws {
        #expect(replied.days == 14)
        #expect(try replied.rows[0].item.repliedAt == date("2026-11-24T10:00:00Z"))
        #expect(replied.rows[1].item.repliedAt == .distantPast)
        #expect(replied.rows[1].item.replied == nil)
        #expect(replied.rows[2].item.repliedAt == nil)
        #expect(replied.rows[2].alreadyArchived)
    }

    @Test func cardsWithEverythingOptionalMissing() throws {
        let row = #"{"item":{"emailKey":"k","ref":{"server":"macia","id":1}}}"#
        guard case .spam(let s) = try card(#"{"spam":{"_0":{"rows":[\#(row)]}}}"#),
              case .clean(let c) = try card(#"{"clean":{"_0":{"rows":[\#(row)]}}}"#),
              case .repliedArchive(let r) = try card(#"{"repliedArchive":{"_0":{"rows":[\#(row)]}}}"#),
              case .spam(let empty) = try card(#"{"spam":{"_0":{}}}"#)
        else { Issue.record("not read"); return }
        // Nothing is offered on a guess: no canDelete, no Delete.
        #expect(labels(view(s), 0) == [["Not spam"], []])
        #expect(view(s).all == nil)
        #expect(view(s).rows[0].sender == "(no sender)")
        #expect(view(s).rows[0].subject == "(no subject)")
        #expect(view(s).rows[0].details.isEmpty)
        #expect(labels(view(c), 0) == [["Keep"], []])
        #expect(r.days == 7)
        #expect(view(r).rows[0].details == ["you replied last"])
        #expect(empty.rows.isEmpty)
    }

    @Test func anUnknownOrUnreadableCardIsKeptAsUnknown() throws {
        #expect(try card(#"{"triageLater":{"_0":{"rows":[]}}}"#) == .unsupported("triageLater"))
        // A row that can't be read: the whole card, never some of its rows under "Move all".
        for kind in ["spam", "clean", "repliedArchive"] {
            #expect(try card(#"{"\#(kind)":{"_0":{"rows":[{"item":{"emailKey":"k","ref":{"server":"macia","id":1}}},{"item":{"subject":"no key"}}]}}}"#)
                    == .unsupported(kind))
        }
    }

    @Test func cardsRoundTrip() throws {
        for card in cards { #expect(try decode(Card.self, json(card)) == card) }
    }

    @Test func refsGoBackExactlyAsReceived() throws {
        #expect(try json(spam.rows[0].item.ref) == #"{"account":"fanda","id":"18c2a","server":"gmail-mcp","threadID":"t-18c2a"}"#)
        #expect(try json(spam.rows[1].item.ref) == #"{"headerMessageID":"<a+b/c=@x.example>","id":40213,"server":"macia"}"#)
        #expect(try json(replied.rows[1].item.ref) == #"{"id":12,"server":"macia"}"#)
        #expect(view(spam).rows[1].ref == spam.rows[1].item.ref)  // what a tap on the row opens
        // The same number, another email.
        var other = spam.rows[1].item.ref
        other.headerMessageID = "<other@x.example>"
        #expect(other != spam.rows[1].item.ref)
    }

    @Test func aDraftsMessageIDGoesBackToo() throws {
        let text = #"{"draftID":"9","headerMessageID":"<d@x.example>","server":"tb","subject":"Hi","to":[]}"#
        #expect(try json(decode(DraftSummary.self, text)) == text)
        let without = #"{"draftID":"9","server":"tb","subject":"Hi","to":[]}"#
        #expect(try json(decode(DraftSummary.self, without)) == without)
    }

    @Test func everyActionsExactJSON() {
        let key = "gmail-mcp|fanda|18c2a"
        let row: [(CardAction, String)] = [
            (.spamDelete(emailKey: key), "spam_delete"), (.spamConfirmAndDelete(emailKey: key), "spam_confirm_and_delete"),
            (.spamKeepAndSkip(emailKey: key), "spam_keep_and_skip"), (.spamDismiss(emailKey: key), "spam_dismiss"),
            (.cleanDelete(emailKey: key), "clean_delete"), (.cleanKeep(emailKey: key), "clean_keep"),
            (.archiveRepliedOne(emailKey: key), "archive_replied_one"), (.archiveRepliedKeep(emailKey: key), "archive_replied_keep"),
        ]
        for (action, name) in row { #expect(action.json.serialized() == #"{"action":"\#(name)","email_key":"\#(key)"}"#) }
        let whole: [(CardAction, String)] = [
            (.spamDeleteAll, "spam_delete_all"), (.spamRefresh, "spam_refresh"), (.cleanDeleteAll, "clean_delete_all"),
            (.cleanRefresh, "clean_refresh"), (.archiveRepliedAll, "archive_replied_all"),
            (.archiveRepliedRefresh, "archive_replied_refresh"),
        ]
        for (action, name) in whole { #expect(action.json.serialized() == #"{"action":"\#(name)"}"#) }
    }

    // MARK: What the cards offer

    @Test func spamButtons() {
        let v = view(spam)
        #expect(v.title == "Caught Spam & Marketing")
        #expect(labels(v, 0) == [["Delete", "Not spam"], ["Add to Spam list & Delete", "Not spam (+ Skip list)"]])
        #expect(labels(v, 1) == [["Delete", "Not spam"], ["Not spam (+ Skip list)"]])  // already on the spam list
        #expect(labels(v, 2) == [["Not spam"], ["Not spam (+ Skip list)"]])  // already deleted
        #expect(labels(v, 3) == [["Not spam"], []])  // no sender, can't delete
        // Can be deleted, but has no sender to list.
        var row = spam.rows[0]
        row.item.from = nil
        #expect(labels(view(SpamCard(rows: [row])), 0) == [["Delete", "Not spam"], []])
        row = spam.rows[0]
        row.item.canDelete = false
        #expect(labels(view(SpamCard(rows: [row])), 0) == [["Not spam"], ["Not spam (+ Skip list)"]])
        // The two that are easy to mix up are kept apart: one behind the menu, saying what else it does.
        #expect(v.rows[0].menu.last?.detail == "Also stops triage checking this sender")
        let key = spam.rows[0].item.emailKey
        #expect(v.rows[0].buttons.map(\.action) == [.spamDelete(emailKey: key), .spamDismiss(emailKey: key)])
        #expect(v.rows[0].menu.map(\.action) == [.spamConfirmAndDelete(emailKey: key), .spamKeepAndSkip(emailKey: key)])
        #expect(v.refresh == .spamRefresh)
        #expect(v.all?.action == .spamDeleteAll)
    }

    @Test func cleanButtons() {
        let v = view(clean)
        #expect(v.title == "Inbox Cleanup")
        #expect(labels(v, 0) == [["Delete", "Keep"], []])
        #expect(labels(v, 1) == [["Keep"], []])
        var row = clean.rows[0]
        row.alreadyDeleted = true
        #expect(labels(view(CleanCard(rows: [row])), 0) == [["Keep"], []])
        #expect(view(CleanCard(rows: [row])).rows[0].mark == "Already deleted")
        #expect(v.rows[0].buttons.map(\.action) == [.cleanDelete(emailKey: "k1"), .cleanKeep(emailKey: "k1")])
        #expect(v.refresh == .cleanRefresh)
        #expect(v.all?.action == .cleanDeleteAll)
    }

    @Test func repliedButtons() {
        let v = view(replied)
        #expect(v.title == "Archive (last 14d)")
        #expect(labels(v, 0) == [["Archive", "Keep"], ["Archive & remember", "Keep & remember"]])
        #expect(labels(v, 2) == [["Keep"], ["Keep & remember"]])
        #expect(v.rows[2].mark == "Already archived")
        #expect(v.rows[0].buttons.map(\.action) == [.archiveRepliedOne(emailKey: "r1"), .archiveRepliedKeep(emailKey: "r1")])
        #expect(v.refresh == .archiveRepliedRefresh)
        #expect(v.all?.action == .archiveRepliedAll)
    }

    @Test func countsOnTheMoveAllButtons() {
        #expect(view(spam).all?.label == "Move all to Trash (2)")  // not the deleted one, nor the one that can't be
        #expect(view(clean).all?.label == "Move all to Trash (1)")
        #expect(view(replied).all?.label == "Archive all (2)")
        #expect(view(spam).all?.confirmation.title == "Move 2 caught emails to Trash?")
        #expect(view(clean).all?.confirmation.title == "Move 1 cleanup item to Trash?")
        #expect(view(replied).all?.confirmation.title == "Archive 2 conversations?")
        // Hidden at 0.
        #expect(view(SpamCard(rows: Array(spam.rows.dropFirst(2)))).all == nil)
        #expect(view(CleanCard(rows: Array(clean.rows.dropFirst()))).all == nil)
        #expect(view(RepliedArchiveCard(rows: Array(replied.rows.dropFirst(2)))).all == nil)
    }

    @Test func rowsSayWhereTheyreFromAndWhy() {
        let rows = view(spam).rows
        #expect(rows.map(\.id) == spam.rows.map(\.item.emailKey))
        #expect(rows[0].sender == "Acme Deals")
        #expect(rows[0].subject == "50% off everything")
        #expect(rows[0].details == ["fanda", "marketing"])
        #expect(rows[0].mark == nil)
        #expect(rows[1].sender == "promo@list.example")
        #expect(rows[1].details == ["on the spam list"])
        #expect(rows[2].mark == "Already deleted")
        #expect(rows[3].sender == "(no sender)")
        #expect(rows[3].subject == "(no subject)")
        #expect(view(replied).rows[0].details == ["fanda", "replied on 2026-11-24"])
        #expect(view(replied).rows[1].details == ["you replied last"])  // Swift's distantPast
        #expect(view(replied).rows[2].details == ["you replied last"])
    }

    @Test func emptyCards() {
        #expect(view(SpamCard()).emptyText == "No caught spam or marketing emails waiting.")
        #expect(view(CleanCard()).emptyText == "No inbox cleanup items waiting.")
        #expect(view(RepliedArchiveCard()).sections.map(\.emptyText) == ["None.", "None judged complete."])
        #expect(view(SpamCard(statusNote: "Moved 3 to Trash.")).emptyText == "Moved 3 to Trash.")
        #expect(view(CleanCard(statusNote: "note")).emptyText == "note")
        #expect(view(RepliedArchiveCard(statusNote: "note")).emptyText == "note")
    }

    @Test func busyOrDisconnectedDisablesEveryButton() {
        for v in [view(spam), view(clean), view(replied)] {
            #expect(v.refreshEnabled)
            #expect(everyButton(v).allSatisfy { $0.enabled })
        }
        for v in [view(spam, busy: true), view(clean, busy: true), view(replied, busy: true),
                  view(spam, connected: false), view(clean, connected: false), view(replied, connected: false)] {
            #expect(!v.refreshEnabled)
            #expect(!everyButton(v).isEmpty)
            #expect(everyButton(v).allSatisfy { !$0.enabled })
        }
    }

    @Test func theCardsAsText() {
        #expect(CardText.describe(cards[0]).hasPrefix("Caught Spam & Marketing\n1. Acme Deals — 50% off everything"))
        #expect(CardText.describe(cards[2]).contains("you replied last · Already archived"))
        #expect(CardText.describe(.clean(CleanCard())) == "Inbox Cleanup\nNo inbox cleanup items waiting.")
    }

    // MARK: Confirmations

    @Test func everyButtonAsksNamingItsEmail() {
        for v in [view(spam), view(clean), view(replied)] {
            for row in v.rows {
                for button in row.buttons + row.menu {
                    #expect(button.confirmation.text.contains(row.sender) && button.confirmation.text.contains(row.subject),
                            "\(button.label)")
                }
            }
        }
        let destructive = [view(spam), view(clean), view(replied)].flatMap(\.rows).flatMap { $0.buttons + $0.menu }
            .filter(\.destructive).map(\.label)
        #expect(Set(destructive) == ["Delete", "Add to Spam list & Delete"])
        #expect(view(spam).rows[0].menu[0].confirmation.text.contains("deals@acme.example"))  // the address that's listed
    }

    @Test func moveAllClosesWhenAnythingOnTheCardChanges() throws {
        let asked = try #require(view(spam).all).confirmation
        #expect(asked.holds(.spam(spam), busy: false, connected: true))
        var changed = spam
        var added = spam.rows[0]
        added.item.emailKey = "new"
        changed.rows.append(added)
        #expect(!asked.holds(.spam(changed), busy: false, connected: true))
        #expect(!asked.holds(.spam(SpamCard(rows: Array(spam.rows.dropFirst()), statusNote: spam.statusNote)), busy: false, connected: true))
        #expect(!asked.holds(.spam(SpamCard(rows: spam.rows, statusNote: "Refreshed.")), busy: false, connected: true))
        #expect(!asked.holds(nil, busy: false, connected: true))  // hidden or deleted
        #expect(!asked.holds(.clean(clean), busy: false, connected: true))
        #expect(!asked.holds(.spam(spam), busy: true, connected: true))
        #expect(!asked.holds(.spam(spam), busy: false, connected: false))
        let archive = try #require(view(replied).all).confirmation
        #expect(archive.holds(.repliedArchive(replied), busy: false, connected: true))
        var fewer = replied
        fewer.rows.removeFirst()
        #expect(!archive.holds(.repliedArchive(fewer), busy: false, connected: true))
        let cleaning = try #require(view(clean).all).confirmation
        #expect(cleaning.holds(.clean(clean), busy: false, connected: true))
        #expect(!cleaning.holds(.clean(CleanCard(rows: Array(clean.rows.dropFirst()))), busy: false, connected: true))
    }

    @Test func aRowsQuestionClosesOnlyWhenItsRowChanges() {
        let asked = view(spam).rows[0].buttons[0].confirmation
        #expect(asked.holds(.spam(spam), busy: false, connected: true))
        #expect(asked.holds(.spam(SpamCard(rows: [spam.rows[0]], statusNote: "x")), busy: false, connected: true))  // others went
        #expect(!asked.holds(.spam(SpamCard(rows: Array(spam.rows.dropFirst()))), busy: false, connected: true))  // it went
        var marked = spam
        marked.rows[0].alreadyDeleted = true
        #expect(!asked.holds(.spam(marked), busy: false, connected: true))
        #expect(!asked.holds(.spam(spam), busy: true, connected: true))
        #expect(!asked.holds(.spam(spam), busy: false, connected: false))
        let keep = view(clean).rows[1].buttons[0].confirmation
        #expect(keep.holds(.clean(clean), busy: false, connected: true))
        #expect(!keep.holds(.clean(CleanCard(rows: [clean.rows[0]])), busy: false, connected: true))
        let archive = view(replied).rows[0].buttons[0].confirmation
        #expect(archive.holds(.repliedArchive(replied), busy: false, connected: true))
        #expect(!archive.holds(.repliedArchive(RepliedArchiveCard()), busy: false, connected: true))
    }
}
