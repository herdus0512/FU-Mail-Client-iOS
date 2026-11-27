import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/MailModels.swift, CalendarBadge). Keep in step with it.

/// The badge on a calendar email (list rows, thread messages), from its `calendarMethod`; nil for none.
public enum CalendarBadge {
    public static func label(_ method: String?) -> String? {
        guard let method = method?.trimmingCharacters(in: .whitespaces).uppercased(), !method.isEmpty else { return nil }
        switch method {
        case "REQUEST", "COUNTER": return "Invite"
        case "REPLY": return "Response"
        case "CANCEL": return "Cancelled"
        default: return "Calendar"
        }
    }

    /// What VoiceOver says: "Calendar: Invite".
    public static func spoken(_ label: String) -> String { "Calendar: \(label)" }
}

extension EmailSummary {
    public var calendarBadge: String? { CalendarBadge.label(calendarMethod) }
}

extension EmailMessage {
    public var calendarBadge: String? { CalendarBadge.label(calendarMethod) }
}
