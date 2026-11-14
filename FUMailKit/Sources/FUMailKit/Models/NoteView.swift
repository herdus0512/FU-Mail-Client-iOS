import Foundation

// Copied from the Mac app (Sources/FUMailCore/Notes/NoteView.swift), the card only. Keep in step with
// it. One change: a section this version doesn't know reads as `.unknown`, so it can't break the card.

/// A section the note card can show.
public enum NoteSection: String, Codable, Sendable, CaseIterable {
    case summary, crm, correspondence
    /// From a newer Mac. Never shown or sent.
    case unknown

    public static var allCases: [NoteSection] { [.summary, .crm, .correspondence] }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        self = NoteSection(rawValue: raw) ?? .unknown
    }
}

/// The note card: which note (picked from a list when the name isn't clear), and what's in it.
public struct NoteViewCard: Codable, Sendable, Hashable {
    public enum Stage: String, Codable, Sendable { case choosing, showing }

    /// The name asked for ("UOB"), if any.
    public var query: String?
    public var stage: Stage
    /// The notes to pick from (choosing): the matches, or every note.
    public var candidates: [NoteCandidate]
    public var chosen: NoteCandidate?
    /// Only this section (`/obsidian UOB crm`), else all three.
    public var only: NoteSection?
    /// "project" or "company".
    public var kind: String?
    public var summary = ""
    public var crm: [NoteEntry] = []
    public var correspondence: [NoteEntry] = []
    /// The sections' names in this vault ("CRM", "Correspondence").
    public var crmSection = "CRM"
    public var correspondenceSection = "Correspondence"
    /// Sections showing every entry, not just the newest few.
    public var expanded: [NoteSection] = []
    /// When the note was read (Refresh reads it again).
    public var readAt: Date?
    /// "Catch me up": a short summary of the recent entries, written on request.
    public var catchUp: ThreadCard.Summary?
    /// The note can take CRM updates (Post CRM update).
    public var canPostCRM = false
    public var problem: String?

    /// How many entries a section shows before Show all.
    public static let recent = 5

    public func shows(_ section: NoteSection) -> Bool { only == nil || only == section }
}
