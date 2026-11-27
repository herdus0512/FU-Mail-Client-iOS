import Foundation
import Testing
@testable import FUMailKit

/// Calendar invitations' badges (the Mac's CalendarBadge).
struct CalendarBadgeTests {
    @Test func labels() {
        #expect(CalendarBadge.label("REQUEST") == "Invite")
        #expect(CalendarBadge.label("counter") == "Invite")
        #expect(CalendarBadge.label(" Reply ") == "Response")
        #expect(CalendarBadge.label("cancel") == "Cancelled")
        #expect(CalendarBadge.label("PUBLISH") == "Calendar")
        #expect(CalendarBadge.label("x-something") == "Calendar")
        #expect(CalendarBadge.label("  ") == nil)
        #expect(CalendarBadge.label("") == nil)
        #expect(CalendarBadge.label(nil) == nil)
        #expect(CalendarBadge.spoken("Invite") == "Calendar: Invite")
    }

    @Test func listRowsWithAndWithoutTheField() throws {
        let card = try decode(EmailListCard.self, #"{"kind":{"inbox":{}},"items":["#
            + #"{"ref":{"server":"tb","id":1},"subject":"Q4 review","unread":true,"calendarMethod":"REQUEST"},"#
            + #"{"ref":{"server":"tb","id":2},"subject":"Lunch","unread":false}],"problems":[],"exclusions":{}}"#)
        #expect(card.items.map(\.calendarMethod) == ["REQUEST", nil])
        #expect(card.items.map(\.calendarBadge) == ["Invite", nil])
    }

    @Test func threadMessagesWithAndWithoutTheField() throws {
        func message(_ id: String, _ extra: String) -> String {
            #"{"id":"\#(id)","to":[],"cc":[],"subject":"S","unread":false,"attachments":[],"body":"","bodyTruncated":false,"quotedRemoved":false\#(extra)}"#
        }
        let card = try decode(ThreadCard.self, #"{"ref":{"server":"tb","id":"a"},"subject":"S","fullText":false,"side":"original","messages":["#
            + message("a", #","calendarMethod":"CANCEL""#) + "," + message("b", #","calendarMethod":"reply","isDraft":true"#) + ","
            + message("c", "") + "]}")
        #expect(card.messages.map(\.calendarBadge) == ["Cancelled", "Response", nil])
        #expect(card.messages[1].isUnsentDraft)  // beside the Draft badge
    }
}
