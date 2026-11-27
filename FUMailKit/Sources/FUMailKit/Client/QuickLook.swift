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

    /// What the on-device model is asked, word for word as the Android app's Summarise & Speak.
    public var summaryInstruction: String {
        switch self {
        case .restOfToday:
            "Below is what's left on my calendar today, one event per line. In one or two short, friendly "
                + "sentences, tell me what's coming up and when I'm free. Don't invent anything."
        case .pendingDrafts:
            "Below are my unsent email drafts, one per line (who it's to, then the subject). In one or two short "
                + "sentences, tell me how many there are and who they're to. Don't invent anything."
        }
    }

    /// What the model is given: the instruction, a blank line, then the lines.
    public func summaryPrompt(_ lines: String) -> String { "\(summaryInstruction)\n\n\(lines)" }

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
