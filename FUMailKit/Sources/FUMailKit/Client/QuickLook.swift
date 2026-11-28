import Foundation

/// What a Home Screen quick action (long-press on the icon) opens, as the Android app's long-press
/// shortcuts: a card asked for at once, without making a chat. The same requests as the Siri actions.
public enum QuickLook: String, Sendable, Identifiable, CaseIterable {
    /// The quick action's type in Info.plist (UIApplicationShortcutItemType).
    case restOfToday = "rest-of-today"
    case pendingDrafts = "pending-drafts"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .restOfToday: "Rest of today"
        case .pendingDrafts: "Pending drafts"
        }
    }

    var path: String {
        switch self {
        case .restOfToday: RestOfToday.path
        case .pendingDrafts: PendingDrafts.path
        }
    }

    /// The card, or why there isn't one (the same sentences as Siri's).
    public enum Answer: Sendable, Equatable {
        case card(Card)
        case problem(String)
    }

    /// What the on-device model is asked for **Summarise & Speak**.
    public var summaryInstruction: String {
        switch self {
        case .restOfToday:
            "Below is what's left on my calendar today, one event per line. In two to three short, friendly "
                + "sentences, tell me how many events are left, which events block which times, and when I'm free. "
                + "Don't invent anything."
        case .pendingDrafts:
            "Below are my unsent email drafts, one per line (who it's to, then the subject). In two to three "
                + "short, friendly sentences, tell me how many drafts there are, who each one is to, and what the "
                + "subject is. Don't invent anything."
        }
    }

    /// What the model is given: the instruction, a blank line, then the lines.
    public func summaryPrompt(_ lines: String) -> String { "\(summaryInstruction)\n\n\(lines)" }

    /// Concise count-only summary for Siri / Shortcuts (`IntentDialog`).
    public static func siriSummary(_ answer: Answer) -> String {
        switch answer {
        case .card(.events(let card)):
            switch card.events.count {
            case 0: "Nothing more on today."
            case 1: "You have 1 event left today."
            case let count: "You have \(count) events left today."
            }
        case .card(.draftList(let card)):
            switch card.items.count {
            case 0: "No drafts waiting."
            case 1: "You have 1 pending draft."
            case let count: "You have \(count) pending drafts."
            }
        case .card: ""
        case .problem(let sentence): sentence
        }
    }

    /// The card as the Siri actions word it (one line each), or the problem's sentence.
    public static func lines(_ answer: Answer, timeZone: TimeZone = .autoupdatingCurrent,
                             locale: Locale = .autoupdatingCurrent) -> String {
        switch answer {
        case .card(.events(let card)): RestOfToday.text(card, timeZone: timeZone, locale: locale)
        case .card(.draftList(let card)): PendingDrafts.text(card)
        case .card: ""
        case .problem(let sentence): sentence
        }
    }

    public func fetch(_ transport: any DesktopTransport) async -> Answer {
        do {
            let data = try await transport.send("GET", path, body: nil)
            return switch self {
            case .restOfToday: .card(.events(try APICoding.decoder.decode(EventListCard.self, from: data)))
            case .pendingDrafts: .card(.draftList(try APICoding.decoder.decode(DraftListCard.self, from: data)))
            }
        } catch {
            return .problem(RestOfToday.sentence(for: error, url: transport.display))
        }
    }
}
