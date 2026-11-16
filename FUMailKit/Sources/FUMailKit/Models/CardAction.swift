import Foundation

// Copied from the Mac app (Sources/FUMailCore/Session/CardAction.swift): the enum and its JSON, the
// body of `POST /v1/conversations/{id}/messages/{messageID}/action`. Keep in step with it.

/// A card's buttons. As JSON it's `{"action": "set_side", "side": "summary"}`.
public enum CardAction: Sendable, Equatable {
    case showFullText
    case toggleFold(emailID: String)
    case setAllUnfolded(Bool)
    case setSide(ThreadCard.Side)
    case summarize(again: Bool)
    /// Opens a draft editor (on the device that asked) with a reply to the card's email.
    case reply(instructions: String, blank: Bool, replyAll: Bool)
    case addToNotes
    /// Opens a draft card's draft in an editor.
    case editDraft
    /// Fetches a Google Mail draft again for its current link (Open in browser); since FU Mail 3.4.0.
    case refreshDraft
    case chooseNote(NoteCandidate)
    case backToChoices
    case editNoteEntry(heading: String?, body: String?)
    case skipNote
    case insertNote(replace: Bool)
    case undoNote
    case updateSuggestion(String)
    case addSuggestion
    case dismissSuggestion
    /// CRM card: the update as edited (Done in its sheet).
    case crmSetText(String)
    /// CRM card: "Rewrite professionally", from this text and these instructions.
    case crmRewrite(text: String, instructions: String)
    case crmChoose(NoteCandidate)
    case crmBack
    case crmPost
    case crmSkip
    /// Note card: open this note (from the list).
    case noteViewChoose(NoteCandidate)
    case noteViewRefresh
    /// Note card: show every entry of a section (or just the newest again).
    case noteViewExpand(NoteSection)
    case noteViewCatchUp
    /// Note card: a CRM card for this note.
    case noteViewPostCRM
    /// Thread card: a new-task card from this email.
    case addTask
    /// Tasks card.
    case tasksRefresh
    case taskComplete(taskID: String)
    /// Undo for Done.
    case taskReopen(taskID: String)
    /// nil removes the due date.
    case taskReschedule(taskID: String, dueDate: String?)
    case taskUpdate(taskID: String, title: String, notes: String, dueDate: String?)
    /// New-task card: the fields as edited (Done in its sheet), then Create or Cancel.
    case taskDraftSet(title: String, list: String, dueDate: String?, notes: String)
    case taskCreate
    case taskDraftCancel
    /// A change asked for in chat: Confirm or Cancel.
    case taskChangeConfirm
    case taskChangeCancel
    /// "Show more" on an archive list: the next page, added to the card.
    case archiveMore

    /// As an API request body.
    public var json: JSONValue {
        func candidate(_ value: NoteCandidate) -> JSONValue {
            (try? JSONValue.parse(JSONEncoder().encode(value))) ?? .null
        }
        return switch self {
        case .showFullText: ["action": "show_full_text"]
        case .toggleFold(let email): ["action": "toggle_fold", "email_id": .string(email)]
        case .setAllUnfolded(let open): ["action": "set_all_unfolded", "open": .bool(open)]
        case .setSide(let side): ["action": "set_side", "side": .string(side.rawValue)]
        case .summarize(let again): ["action": "summarize", "again": .bool(again)]
        case .reply(let instructions, let blank, let replyAll):
            ["action": "reply", "instructions": .string(instructions), "blank": .bool(blank), "reply_all": .bool(replyAll)]
        case .addToNotes: ["action": "add_to_notes"]
        case .editDraft: ["action": "edit_draft"]
        case .refreshDraft: ["action": "refresh_draft"]
        case .chooseNote(let value): ["action": "choose_note", "candidate": candidate(value)]
        case .backToChoices: ["action": "back_to_choices"]
        case .editNoteEntry(let heading, let body):
            ["action": "edit_note_entry", "heading": heading.map(JSONValue.string) ?? .null,
             "body": body.map(JSONValue.string) ?? .null]
        case .skipNote: ["action": "skip_note"]
        case .insertNote(let replace): ["action": "insert_note", "replace": .bool(replace)]
        case .undoNote: ["action": "undo_note"]
        case .updateSuggestion(let text): ["action": "update_suggestion", "text": .string(text)]
        case .addSuggestion: ["action": "add_suggestion"]
        case .dismissSuggestion: ["action": "dismiss_suggestion"]
        case .crmSetText(let text): ["action": "crm_set_text", "text": .string(text)]
        case .crmRewrite(let text, let instructions):
            ["action": "crm_rewrite", "text": .string(text), "instructions": .string(instructions)]
        case .crmChoose(let value): ["action": "crm_choose", "candidate": candidate(value)]
        case .crmBack: ["action": "crm_back"]
        case .crmPost: ["action": "crm_post"]
        case .crmSkip: ["action": "crm_skip"]
        case .noteViewChoose(let value): ["action": "note_view_choose", "candidate": candidate(value)]
        case .noteViewRefresh: ["action": "note_view_refresh"]
        case .noteViewExpand(let section): ["action": "note_view_expand", "section": .string(section.rawValue)]
        case .noteViewCatchUp: ["action": "note_view_catch_up"]
        case .noteViewPostCRM: ["action": "note_view_post_crm"]
        case .addTask: ["action": "add_task"]
        case .tasksRefresh: ["action": "tasks_refresh"]
        case .taskComplete(let task): ["action": "task_complete", "task_id": .string(task)]
        case .taskReopen(let task): ["action": "task_reopen", "task_id": .string(task)]
        case .taskReschedule(let task, let due):
            ["action": "task_reschedule", "task_id": .string(task), "due_date": .string(due ?? "")]
        case .taskUpdate(let task, let title, let notes, let due):
            ["action": "task_update", "task_id": .string(task), "title": .string(title), "notes": .string(notes),
             "due_date": .string(due ?? "")]
        case .taskDraftSet(let title, let list, let due, let notes):
            ["action": "task_draft_set", "title": .string(title), "list": .string(list), "due_date": .string(due ?? ""),
             "notes": .string(notes)]
        case .taskCreate: ["action": "task_create"]
        case .taskDraftCancel: ["action": "task_draft_cancel"]
        case .taskChangeConfirm: ["action": "task_change_confirm"]
        case .taskChangeCancel: ["action": "task_change_cancel"]
        case .archiveMore: ["action": "archive_more"]
        }
    }
}

extension NoteFile {
    /// For the "None of these…" filter: the title, `related:` names, stakeholders or path contain it.
    public func matches(_ filter: String) -> Bool {
        let words = filter.trimmingCharacters(in: .whitespaces)
        guard !words.isEmpty else { return true }
        return ([title, path] + related + stakeholders).contains { $0.localizedCaseInsensitiveContains(words) }
    }

    /// "None of these…" on a notes card: the reason the Mac gives.
    public var asNotesCandidate: NoteCandidate {
        NoteCandidate(path: path, title: title, reason: "chosen from all notes", score: 0)
    }

    /// "None of these…" on a CRM card.
    public var asCRMCandidate: NoteCandidate {
        NoteCandidate(path: path, title: title, reason: "chosen from the list", score: 0)
    }
}
