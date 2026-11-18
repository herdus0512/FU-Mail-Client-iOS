import Foundation

// Copied from the Mac app (Sources/FUMailCore/Notes/Notes.swift, NoteMatcher.swift, CRM.swift and
// Memory/Learning.swift): the cards and the notes they list. Keep in step with it.

/// A note that an entry can go into, as the Mac read it from the vault.
public struct NoteFile: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// Path inside the vault, e.g. "ignivo/project/Agentic SOC for UOB.md".
    public var path: String
    /// The `# Title`, else the file name.
    public var title: String
    /// Names from `related: ["[[UOB]]", …]` in the frontmatter.
    public var related: [String]
    /// `### Customer - UOB` under `## Stakeholders` → "UOB" (and the role).
    public var stakeholders: [String]
    /// Empty in the API's note lists (kept small).
    public var summary: String
    /// `[]` in the API's note lists.
    public var entries: [NoteEntry]
    /// The first tag under `## Tag` (e.g. "project").
    public var firstTag: String? = nil

    public var id: String { path }

    /// Every name the note is about: its title, related links and stakeholders.
    public var names: [String] { [title] + related + stakeholders }

    /// "project" or "company": its first tag, else (no tag) the folder it's in.
    public var kind: String? {
        if let firstTag { return firstTag.lowercased() }
        return path.split(separator: "/").dropLast().last.map { $0.lowercased() }
    }
}

/// One `### …` entry in a note's section: its heading and the lines under it.
public struct NoteEntry: Sendable, Equatable, Hashable, Codable {
    public var heading: String
    public var lines: [String]

    public init(heading: String, lines: [String]) {
        self.heading = heading
        self.lines = lines
    }

    public var block: [String] { [heading] + lines }
    public var text: String { block.joined(separator: "\n") }
    /// The lines under the heading as one text, for editing.
    public var body: String { lines.joined(separator: "\n") }
}

/// A note suggested for an entry, and why.
public struct NoteCandidate: Codable, Sendable, Hashable, Identifiable {
    public var path: String
    public var title: String
    public var reason: String
    public var score: Double
    public var id: String { path }

    public init(path: String, title: String, reason: String, score: Double) {
        self.path = path
        self.title = title
        self.reason = reason
        self.score = score
    }
}

/// An entry already in the note that looks like the same email.
public struct DuplicateMatch: Codable, Sendable, Hashable {
    public var entry: NoteEntry
    /// The same Gmail link (certain), rather than similar wording (likely).
    public var exact: Bool
}

/// The "Add to note" card: suggested notes, then a preview to edit, then inserted (with Undo).
public struct NotesCard: Codable, Sendable, Hashable {
    public enum Stage: String, Codable, Sendable { case choosing, preview, inserted, skipped, undone }

    public var stage: Stage
    public var ref: EmailRef
    public var subject: String
    public var sender: String?
    public var candidates: [NoteCandidate]
    public var chosen: NoteCandidate?
    /// The entry to write: editable in the preview.
    public var entry: NoteEntry
    /// An entry already there that looks like the same email.
    public var duplicate: DuplicateMatch?
    /// What was written, and what it replaced, for Undo.
    public var written: NoteEntry?
    public var replaced: NoteEntry?
    /// Whether the section heading was added with the entry (so Undo takes it away too).
    public var createdSection: Bool
    public var problem: String?
    /// The email's Gmail link and date.
    public var link: String?
    public var date: Date
    /// For remembering the note chosen ("domain:…", "thread:…").
    public var choiceKeys: [String]
    /// After writing (FU Mail 4.5.0 and later): where the entry went, "Memos" or "vault".
    public var savedTo: String?
    /// After writing: why the vault was used, when Memos couldn't be reached.
    public var notice: String?
}

/// The "Send to CRM" card: the update, the project note, a preview, and Post.
public struct CRMCard: Codable, Sendable, Hashable {
    public enum Stage: String, Codable, Sendable { case choosing, preview, posted, skipped }

    /// The update as you wrote it (cleaned only when previewed and posted).
    public var text: String
    /// The note asked for by name, when there was one ("UOB").
    public var noteHint: String?
    public var candidates: [NoteCandidate]
    public var chosen: NoteCandidate?
    public var stage: Stage = .choosing
    /// Exactly the lines that will be written: the heading, then the cleaned update.
    public var entry: [String] = []
    /// Whether `## CRM` will be created, and before which heading (nil: at the end).
    public var createsSection = false
    public var createsBefore: String?
    /// You already have an entry dated today in this note.
    public var postedToday = false
    /// "Rewrite professionally" is running (its text streams into `text`).
    public var rewriting = false
    /// e.g. "draft · gemini-3.5-flash-lite"
    public var rewrittenBy: String?
    /// Why the last step didn't work.
    public var problem: String?
    /// After posting: the sync command's outcome ("Synced", or its error).
    public var syncStatus: String?
    /// After writing (FU Mail 4.5.0 and later): where the entry went, "Memos" or "vault".
    public var savedTo: String?
    /// After writing: why the vault was used, when Memos couldn't be reached.
    public var notice: String?
}

/// A note for memory.md, suggested from your edits. Written only when you say so.
public struct SuggestedNoteCard: Codable, Sendable, Hashable {
    public enum State: String, Codable, Sendable { case suggested, added, dismissed }

    /// `Rules` or `People`.
    public var section: String
    /// One bullet, e.g. "- Bob Smith: prefers short replies."
    public var note: String
    /// What it was learnt from, e.g. the reply's subject or "your last 4 edits".
    public var source: String
    public var state: State
    /// Where it was added, once it is.
    public var addedTo: String?

    public init(section: String, note: String, source: String, state: State = .suggested, addedTo: String? = nil) {
        self.section = section
        self.note = note
        self.source = source
        self.state = state
        self.addedTo = addedTo
    }
}

public enum Notes {
    /// A note kept in Memos rather than the vault: "memos/abc123" (a vault file ends in ".md").
    public static func isMemo(_ path: String) -> Bool {
        path.hasPrefix("memos/") && !path.hasSuffix(".md")
    }

    /// The web link that opens memo `path` ("memos/abc123") on the Memos server at `memosURL`.
    public static func memosURL(path: String, memosURL: String) -> URL? {
        let base = memosURL.hasSuffix("/") ? String(memosURL.dropLast()) : memosURL
        guard !base.isEmpty, isMemo(path) else { return nil }
        return URL(string: base + "/" + path)
    }

    /// "Added to UOB" with where it went: "Added to UOB (Memos)", "… (vault)"; unchanged without it.
    public static func withPlace(_ line: String, savedTo: String?) -> String {
        guard let savedTo, !savedTo.isEmpty else { return line }
        return "\(line) (\(savedTo))"
    }

    /// The obsidian:// link that opens note `path` in the vault named `vault`.
    public static func obsidianURL(path: String, vault: String) -> URL? {
        var components = URLComponents()
        components.scheme = "obsidian"
        components.host = "open"
        components.queryItems = [URLQueryItem(name: "vault", value: vault),
                                 URLQueryItem(name: "file", value: path.hasSuffix(".md") ? String(path.dropLast(3)) : path)]
        return components.url
    }
}
