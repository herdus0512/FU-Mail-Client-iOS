import Foundation

// Copied from the Mac app (Sources/FUMailCore/Triage/TriageSpamList.swift, TriageCleanList.swift and
// TriageArchiveList.swift): the cards of /triage spam, clean and archive, which the Mac sends only to a
// device named in its api.full_triage. Keep in step with it. One change: a field that's missing is read
// as its empty value (a flag as false, so a delete is never offered on a guess), and `kind` is any text.
// What the cards show and offer is in Rules/TriageRules.swift. A row that can't be read makes the whole
// card `.unsupported`: never some of its rows under "Move all".

/// One email caught by triage as spam or marketing.
public struct TriageSpamItem: Codable, Sendable, Hashable {
    /// Sent back unchanged as `email_key`.
    public var emailKey: String
    public var ref: EmailRef
    public var from: EmailAddress?
    public var subject: String
    public var received: Date?
    public var reason: String
    /// The sender is already on the spam list.
    public var fromSpamList: Bool
    public var caughtAt: Date?
    public var canDelete: Bool

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        emailKey = try values.decode(String.self, forKey: .emailKey)
        ref = try values.decode(EmailRef.self, forKey: .ref)
        from = try values.decodeIfPresent(EmailAddress.self, forKey: .from)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        received = try values.decodeIfPresent(Date.self, forKey: .received)
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? ""
        fromSpamList = try values.decodeIfPresent(Bool.self, forKey: .fromSpamList) ?? false
        caughtAt = try values.decodeIfPresent(Date.self, forKey: .caughtAt)
        canDelete = try values.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    }
}

/// `/triage spam`.
public struct SpamCard: Codable, Sendable, Hashable {
    public struct Row: Codable, Sendable, Hashable {
        public var item: TriageSpamItem
        public var alreadyDeleted: Bool

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            item = try values.decode(TriageSpamItem.self, forKey: .item)
            alreadyDeleted = try values.decodeIfPresent(Bool.self, forKey: .alreadyDeleted) ?? false
        }

        /// Offered Delete, and moved by "Move all to Trash".
        public var canDelete: Bool { item.canDelete && !alreadyDeleted }
    }

    public var rows: [Row]
    public var statusNote: String?

    public init(rows: [Row] = [], statusNote: String? = nil) {
        self.rows = rows
        self.statusNote = statusNote
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rows = try values.decodeIfPresent([Row].self, forKey: .rows) ?? []
        statusNote = try values.decodeIfPresent(String.self, forKey: .statusNote)
    }
}

/// One non-spam inbox item caught by triage, e.g. a calendar response.
public struct TriageCleanItem: Codable, Sendable, Hashable {
    /// Sent back unchanged as `email_key`.
    public var emailKey: String
    public var ref: EmailRef
    public var from: EmailAddress?
    public var subject: String
    public var received: Date?
    /// "calendarResponse", or a kind from a later Mac.
    public var kind: String
    public var reason: String
    public var caughtAt: Date?
    public var canDelete: Bool

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        emailKey = try values.decode(String.self, forKey: .emailKey)
        ref = try values.decode(EmailRef.self, forKey: .ref)
        from = try values.decodeIfPresent(EmailAddress.self, forKey: .from)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        received = try values.decodeIfPresent(Date.self, forKey: .received)
        kind = try values.decodeIfPresent(String.self, forKey: .kind) ?? ""
        reason = try values.decodeIfPresent(String.self, forKey: .reason) ?? ""
        caughtAt = try values.decodeIfPresent(Date.self, forKey: .caughtAt)
        canDelete = try values.decodeIfPresent(Bool.self, forKey: .canDelete) ?? false
    }
}

/// `/triage clean`.
public struct CleanCard: Codable, Sendable, Hashable {
    public struct Row: Codable, Sendable, Hashable {
        public var item: TriageCleanItem
        public var alreadyDeleted: Bool

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            item = try values.decode(TriageCleanItem.self, forKey: .item)
            alreadyDeleted = try values.decodeIfPresent(Bool.self, forKey: .alreadyDeleted) ?? false
        }

        /// Offered Delete, and moved by "Move all to Trash".
        public var canDelete: Bool { item.canDelete && !alreadyDeleted }
    }

    public var rows: [Row]
    public var statusNote: String?

    public init(rows: [Row] = [], statusNote: String? = nil) {
        self.rows = rows
        self.statusNote = statusNote
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rows = try values.decodeIfPresent([Row].self, forKey: .rows) ?? []
        statusNote = try values.decodeIfPresent(String.self, forKey: .statusNote)
    }
}

/// One Inbox email you've already replied to.
public struct TriageArchiveItem: Codable, Sendable, Hashable {
    /// Sent back unchanged as `email_key`.
    public var emailKey: String
    public var ref: EmailRef
    public var from: EmailAddress?
    public var subject: String
    public var received: Date?
    /// Swift's `distantPast` (year 1) when the Mac knows you replied, but not when: see `replied`.
    public var repliedAt: Date?

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        emailKey = try values.decode(String.self, forKey: .emailKey)
        ref = try values.decode(EmailRef.self, forKey: .ref)
        from = try values.decodeIfPresent(EmailAddress.self, forKey: .from)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        received = try values.decodeIfPresent(Date.self, forKey: .received)
        repliedAt = try values.decodeIfPresent(Date.self, forKey: .repliedAt)
    }

    /// When you replied, if that's known.
    public var replied: Date? { repliedAt.flatMap { $0.timeIntervalSince1970 > 0 ? $0 : nil } }
}

/// `/triage archive [days]`.
public struct RepliedArchiveCard: Codable, Sendable, Hashable {
    public struct Row: Codable, Sendable, Hashable {
        public var item: TriageArchiveItem
        public var alreadyArchived: Bool

        public init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            item = try values.decode(TriageArchiveItem.self, forKey: .item)
            alreadyArchived = try values.decodeIfPresent(Bool.self, forKey: .alreadyArchived) ?? false
        }
    }

    public var rows: [Row]
    public var days: Int
    public var statusNote: String?

    public init(rows: [Row] = [], days: Int = 7, statusNote: String? = nil) {
        self.rows = rows
        self.days = days
        self.statusNote = statusNote
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        rows = try values.decodeIfPresent([Row].self, forKey: .rows) ?? []
        days = try values.decodeIfPresent(Int.self, forKey: .days) ?? 7
        statusNote = try values.decodeIfPresent(String.self, forKey: .statusNote)
    }
}
