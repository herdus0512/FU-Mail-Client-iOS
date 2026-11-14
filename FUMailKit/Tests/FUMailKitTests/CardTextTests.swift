import Foundation
import Testing
@testable import FUMailKit

/// Cards as text, on a fixed day in UTC (Saturday 14 November 2026).
struct CardTextTests {
    private let utc = TimeZone(identifier: "UTC")!
    private let saturday = Date(timeIntervalSince1970: 1_794_657_600)  // 2026-11-14T12:00:00Z

    private func text(_ card: Card) -> String { CardText.describe(card, timeZone: utc, now: saturday) }

    @Test func aListNumbersItsRowsAndMarksUnread() throws {
        let card = try decode(Card.self, try fixture("list-card.json"))
        #expect(text(card) == """
            Unread
            1. ● Bob — Q4  Fri 6 Nov 21:20
            2. carol@example.com — Lunch  Thu 5 Nov 09:00
            """)
    }

    @Test func anArchiveListSaysHowManyMore() throws {
        let card = try decode(Card.self, try fixture("archive.json"))
        #expect(text(card).hasSuffix("(20 more)"))
    }

    @Test func aThreadShowsItsOriginalOrItsSummary() throws {
        guard case .thread(var thread) = try decode(ChatMessage.self, try fixture("thread-message.json")).card else { return }
        #expect(text(.thread(thread)) == "Q4\n\nBob  Fri 6 Nov 21:20\nHi\n📎 a.pdf")
        thread.side = .summary
        #expect(text(.thread(thread)) == "Q4\n- Bob wants approval")
        thread.summary?.state = .failed("timed out")
        #expect(text(.thread(thread)) == "Q4\nCouldn't summarise: timed out")
    }

    @Test func otherCards() throws {
        let cards = try decode([Card].self, try fixture("other-cards.json"))
        #expect(text(cards[0]) == "Drafts\n1. To Bob <bob@example.com> — Re: Q4\n⚠ macia: can't save drafts")
        #expect(text(cards[1]) == "Draft: Re: Q4\nTo: Bob <bob@example.com>\n\nThanks Bob")
        #expect(text(cards[2]) == "Next 7 days\nSat 14 Nov 09:00  Standup")
        #expect(text(cards[3]) == "Events: bob (next 30 days)\nNo events matched.")
        #expect(text(cards[4]).hasPrefix("Add to note: Q4\n→ UOB\n### 261106: Q4 Approval"))
        #expect(text(cards[5]) == "Suggested note for People\n- Bob Smith: prefers short replies.")
        #expect(text(cards[6]) == "(A “someFutureCard” card this version can't show yet.)")
    }

    @Test func tasksGroupedAgainstToday() throws {
        let cards = try decode([Card].self, try fixture("tasks.json"))
        #expect(text(cards[0]) == """
            Tasks: Urgent
            Overdue
            ☑ Pay invoice  (Tue 10 Nov)
            Upcoming
            ☐ Dentist  (Fri 20 Nov)
            No date
            ☐ Read report
            """)
        #expect(text(cards[1]) == "New task\nCall Bob\nDue Fri 20 Nov · Inbox")
        #expect(text(cards[2]) == "Dentist\nMove it to Mon 23 Nov?")
        #expect(text(cards[3]) == "Dentist\nDone.")
        #expect(text(cards[4]) == "Pay invoice\nCancelled.")
    }

    @Test func noteCards() throws {
        let cards = try decode([Card].self, try fixture("note-view.json"))
        let showing = text(cards[0])
        #expect(showing.hasPrefix("A\nFrank is meeting UOB on Monday.\n\nCRM\n### 261113: fyoo"))
        #expect(showing.hasSuffix("(1 older)"))
        #expect(text(cards[1]) == "Notes matching “ntt”\n• NTT Data\n• NTT Migration")
        #expect(text(cards[2]) == "CRM update → A\n### 261113: fyoo")
    }
}
