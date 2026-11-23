import Foundation

// How the cards show what the Mac sent, as the Mac's own window and the Android app do. The rules
// that live on the Mac's types (folding, reply targets) are in Models; these are the phone's own.

extension ThreadCard {
    /// Newest first, as the thread card shows them (the card's own order is oldest first).
    public var newestFirst: [EmailMessage] { messages.reversed() }

    /// Only messages the reader unfolded can be folded again (the Mac's chevron).
    public func canFoldAgain(_ message: EmailMessage) -> Bool {
        unfolded?.contains(message.id) == true && !isOpenByDefault(message)
    }

    /// The thread card's Expand all / Fold older button, on the Original side of a thread of more than one.
    public enum FoldAllButton: Sendable { case expandAll, foldOlder }

    public var foldAllButton: FoldAllButton? {
        guard side == .original, messages.count > 1 else { return nil }
        if foldedCount > 0 { return .expandAll }
        return unfolded != nil ? .foldOlder : nil
    }

    /// Whether Reply all is offered: live mail where it reaches someone a plain reply doesn't.
    public var offersReplyAll: Bool {
        archived != true && Drafts.canReplyAll(ReplyContext(thread: self))
    }

    /// The header tabs on a thread card: Original | HTML | Summary on live mail when the server
    /// supports HTML, else Original | Summary.
    public enum HeaderTab: String, Sendable, Hashable {
        case original
        case html
        case summary

        public var label: String {
            switch self {
            case .original: "Original"
            case .html: "HTML"
            case .summary: "Summary"
            }
        }
    }

    public var offersHTMLTab: Bool {
        canShowHTML == true && archived != true && deleted != true
    }

    public var headerTabs: [HeaderTab] {
        offersHTMLTab ? [.original, .html, .summary] : [.original, .summary]
    }

    public var activeHeaderTab: HeaderTab {
        if side == .summary { return .summary }
        if offersHTMLTab, showingHTML == true { return .html }
        return .original
    }

    /// Whether attachments on this thread can be saved to the Mac's configured download folder.
    public var offersAttachmentDownload: Bool {
        canDownloadAttachments == true && archived != true && deleted != true
    }

    /// Whether Archive is offered: live mail that can be archived and hasn't been deleted or archived yet.
    public var offersArchive: Bool {
        canArchive == true && archived != true && deleted != true && movedToArchive != true
    }
}

extension TaskListCard {
    /// The tasks not done yet (done ones stay on the card, struck through, until it's read again).
    public var openCount: Int { tasks.filter { !$0.completed }.count }
}

extension TaskDraftCard {
    /// Create: only while editing, with a title, and not while one's being suggested (or the card is busy).
    public func canCreate(busy: Bool) -> Bool {
        stage == .editing && !busy && !suggestingTitle && !title.isEmpty
    }
}

extension NoteViewCard {
    /// The entries to show for a section: all when expanded, else the newest few.
    public func shown(_ section: NoteSection, _ entries: [NoteEntry]) -> [NoteEntry] {
        expanded.contains(section) ? entries : Array(entries.prefix(Self.recent))
    }
}
