import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/Calendar.swift). Keep in step with it.

/// One calendar event, as GMail-MCP and MacIA return it (read-only).
public struct CalendarEvent: Codable, Sendable, Hashable, Identifiable {
    public var server: String
    public var account: String?
    public var eventID: String
    public var title: String
    public var start: Date?
    public var end: Date?
    public var allDay: Bool
    public var location: String?
    public var videoLink: String?
    public var calendar: String?
    /// accepted, declined, tentative, not_responded, organizer
    public var myResponse: String?
    public var organizedByMe: Bool
    public var attendeeCount: Int?
    public var recurring: Bool
    /// "tentative" when the event itself is.
    public var status: String?

    public var id: String { "\(server)/\(account ?? "")/\(eventID)/\(start?.timeIntervalSince1970 ?? 0)" }
}

public struct EventListCard: Codable, Sendable, Hashable {
    public enum Kind: Codable, Sendable, Hashable {
        case days(Int)
        case search(String, days: Int)
    }

    public var kind: Kind
    public var events: [CalendarEvent]
    public var problems: [String]
    /// How many duplicates (the same event from two servers) were left out.
    public var duplicatesRemoved: Int
    /// `/now` (FU Mail 4.3.0 and later): when it was asked; only what's left of today from then.
    public var from: Date?
    /// `/now`: the time zone its day was counted in, e.g. "Europe/London" (the device's, sent with
    /// every request, else the Mac's).
    public var timeZone: String?

    public var title: String {
        if from != nil { return timeZone.map { "Now (\($0))" } ?? "Now" }
        return switch kind {
        case .days(1): "Today"
        case .days(let days): "Next \(days) days"
        case .search(let words, let days): "Events: \(words) (next \(days) days)"
        }
    }

    public var emptyText: String {
        if from != nil { return "Nothing more on today." }
        return switch kind {
        case .days(1): "Nothing on today."
        case .days: "Nothing on."
        case .search: "No events matched."
        }
    }
}
