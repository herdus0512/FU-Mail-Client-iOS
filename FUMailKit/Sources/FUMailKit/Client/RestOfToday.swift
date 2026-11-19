import Foundation

/// "Rest of Today" for Siri and Shortcuts: `GET /v1/calendar/now` (FU Mail 4.6.0 and later), what's left
/// of today's events, answered at once without a chat, turned into plain lines a shortcut can pass on
/// (to "Use Model", say) and Siri can read out. Never throws: a problem comes back as a sentence.
public enum RestOfToday {
    public static let path = "/v1/calendar/now"

    /// The Mac's answer as text, or why there isn't one.
    public static func fetch(_ transport: any DesktopTransport, timeZone: TimeZone = .autoupdatingCurrent,
                             locale: Locale = .autoupdatingCurrent) async -> String {
        do {
            let data = try await transport.send("GET", path, body: nil)
            let card = try APICoding.decoder.decode(EventListCard.self, from: data)
            return text(card, timeZone: timeZone, locale: locale)
        } catch {
            return sentence(for: error, url: transport.display)
        }
    }

    /// One line per event in the phone's time: "14:00–15:00 Board meeting (Level 3)", "16:30–17:00 Call
    /// with Bob (video call)", "All day: Public holiday"; "Nothing more on today." when there's none.
    /// A calendar that couldn't be read adds a line at the end.
    public static func text(_ card: EventListCard, timeZone: TimeZone = .autoupdatingCurrent,
                            locale: Locale = .autoupdatingCurrent) -> String {
        let time = Date.FormatStyle(date: .omitted, time: .shortened, locale: locale, timeZone: timeZone)
        var lines = card.events.map { event -> String in
            var where_ = [String]()
            if let location = event.location, !location.isEmpty { where_.append(location) }
            if event.videoLink != nil { where_.append("video call") }
            let title = event.title + (where_.isEmpty ? "" : " (\(where_.joined(separator: ", ")))")
            if event.allDay { return "All day: \(title)" }
            guard let start = event.start else { return title }
            let span = start.formatted(time) + (event.end.map { "–" + $0.formatted(time) } ?? "")
            return "\(span) \(title)"
        }
        if lines.isEmpty { lines = ["Nothing more on today."] }
        lines += card.problems
        return lines.joined(separator: "\n")
    }

    /// A problem in plain words, the same ones the app shows (token refused, Cloudflare Access, the Mac
    /// not answering…).
    public static func sentence(for error: Error, url: String) -> String {
        if error is DecodingError {
            return "FU Mail on your Mac sent something this app couldn't read. It may need FU Mail 4.6.0 or later."
        }
        return Problems.describe(error, url: url).message
    }

    /// When the phone has no address or token saved yet.
    public static let notSetUp = "FU Mail isn't connected to your Mac yet. Open the app and set it up first."
}
