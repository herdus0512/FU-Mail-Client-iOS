import Foundation

/// "Pending Drafts" for Siri and Shortcuts: `GET /v1/drafts?limit=10`, the unsent drafts across accounts,
/// as plain lines. Never throws: a problem comes back as the same sentences as `RestOfToday`.
public enum PendingDrafts {
    public static let path = "/v1/drafts?limit=10"

    public static func fetch(_ transport: any DesktopTransport) async -> String {
        do {
            let data = try await transport.send("GET", path, body: nil)
            return text(try APICoding.decoder.decode(DraftListCard.self, from: data))
        } catch {
            return RestOfToday.sentence(for: error, url: transport.display)
        }
    }

    /// "To Bob Smith: Re: Q4 invoice (work)", one per draft; "No drafts waiting." when there's none.
    public static func text(_ card: DraftListCard) -> String {
        var lines = card.items.map { draft -> String in
            let first = draft.to.first.map { $0.name.flatMap { $0.isEmpty ? nil : $0 } ?? $0.email } ?? "(no recipient)"
            let more = draft.to.count > 1 ? " +\(draft.to.count - 1)" : ""
            let subject = draft.subject.isEmpty ? "(no subject)" : draft.subject
            let account = draft.account.flatMap { $0.isEmpty ? nil : " (\($0))" } ?? ""
            return "To \(first)\(more): \(subject)\(account)"
        }
        if lines.isEmpty { lines = ["No drafts waiting."] }
        return (lines + card.problems).joined(separator: "\n")
    }
}
