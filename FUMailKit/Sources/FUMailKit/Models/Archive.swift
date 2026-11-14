import Foundation

// Copied from the Mac app (Sources/FUMailCore/Mail/Archive.swift): what an archive list carries for
// "Show more". The search itself runs on the Mac. Keep in step with it.

/// A search of the mail archive (BCC-MCP), in the archive's own arguments.
public struct ArchiveSearch: Codable, Sendable, Hashable {
    public enum Direction: String, Codable, Sendable, Hashable, CaseIterable {
        case sent
        case received
    }

    public var query: String?
    public var person: String?
    public var since: String?
    public var until: String?
    public var direction: Direction?
    public var limit: Int
}

/// What "Show more" on an archive list needs: the search, and each archive's next page.
public struct ArchivePaging: Codable, Sendable, Hashable {
    public var search: ArchiveSearch
    /// `next_page_token` by server name, only for servers that have more.
    public var tokens: [String: String]
    /// Matches across the archives, when they say (`total`).
    public var total: Int?
}

extension EmailListCard {
    /// How many more an archive list can show, when the archives said how many matched.
    public var remainingCount: Int? {
        guard let more, let total = more.total else { return nil }
        return max(total - items.count, 0)
    }
}
