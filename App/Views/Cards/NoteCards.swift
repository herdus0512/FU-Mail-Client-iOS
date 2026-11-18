import FUMailKit
import SwiftUI

// The cards for notes, as the Mac and the Android app show them: "Add to note", "Send to CRM", the
// note card (`/obsidian`) and suggested notes. What's typed in their sheets stays on this device
// until Done; the buttons that write (Insert, Post, Add) are on the cards.

private struct CardBody<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DoneLine: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "checkmark.circle")
            .appFont(.subheadline)
            .foregroundStyle(StatusColors.connected)
    }
}

private struct Secondary: View {
    var text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).appFont(.caption).foregroundStyle(.secondary)
    }
}

/// Exactly the text that will be (or was) written, in a box.
private struct EntryBox: View {
    var lines: [String]
    var heading: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let heading { Text(heading).appFont(.subheadline, weight: .semibold) }
            ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                Text(line.isEmpty ? " " : line).appFont(.subheadline)
            }
        }
        .copyable(([heading].compactMap { $0 } + lines).joined(separator: "\n"))
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color(.separator).opacity(0.5)))
    }
}

/// The suggested notes: the first is the best match.
private struct CandidateRows: View {
    var candidates: [NoteCandidate]
    var onChoose: (NoteCandidate) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
                Button {
                    onChoose(candidate)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(candidate.title)
                            .appFont(.subheadline, weight: index == 0 ? .semibold : .regular)
                            .foregroundStyle(.tint)
                        if !candidate.reason.isEmpty { Secondary(candidate.reason) }
                    }
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Memos couldn't be reached, so the entry went to the vault: a small warning line, as on the Mac.
private struct NoticeLine: View {
    var text: String

    var body: some View {
        Label { Text(text) } icon: { Image(systemName: "icloud.slash") }
            .appFont(.footnote)
            .foregroundStyle(StatusColors.warning)
    }
}

/// Opens a note where it's kept: a memo ("memos/…") in Memos, in the browser (not shown when the Mac
/// doesn't say where Memos is); a vault file in Obsidian on this device (its vault synced here under
/// the same name).
private struct NoteButton: View {
    var path: String
    var scope: CardScope
    @Environment(\.openURL) private var openURL
    @State private var problem: String?

    var body: some View {
        if Notes.isMemo(path) {
            if let url = scope.client.memosURL(path) {
                Button("Open in Memos") { openURL(url) }
            }
        } else {
            obsidian
        }
    }

    private var obsidian: some View {
        Button("Open in Obsidian") {
            guard let url = scope.client.obsidianURL(path) else {
                problem = "The Mac didn't say which Obsidian vault this note is in."
                return
            }
            openURL(url) { opened in
                if !opened { problem = "Obsidian isn't installed on this device." }
            }
        }
        .alert("Can't open the note", isPresented: Binding(get: { problem != nil }, set: { if !$0 { problem = nil } })) {
            Button("OK") {}
        } message: {
            Text(problem ?? "")
        }
    }
}

private struct TeamVisible: View {
    var text: String

    var body: some View {
        Label(text, systemImage: "person.3")
            .appFont(.caption2)
            .foregroundStyle(StatusColors.warning)
    }
}

// MARK: - Suggested note

struct SuggestedNoteCardView: View {
    var card: SuggestedNoteCard
    var scope: CardScope
    @State private var editing = false

    private var canAdd: Bool { scope.info?.canAddSuggestions == true }

    var body: some View {
        CardBox {
            CardHeader(title: "Suggested note", detail: "for ## \(card.section) · from \(card.source)")
            Divider()
            CardBody {
                switch card.state {
                case .suggested:
                    Text(card.note).appFont(.subheadline)
                    Secondary("Not added unless you choose to")
                    if !canAdd { Secondary("memory.path is \"none\" in the Mac's config, so there's no file to add it to.") }
                case .added: DoneLine(text: "Added to \(card.addedTo ?? "memory.md")")
                case .dismissed: Secondary("Dismissed")
                }
            }
            if card.state == .suggested {
                CardActions {
                    Button("Edit…") { editing = true }
                    Button("Add to my memory.md") { scope.act(.addSuggestion) }.disabled(!canAdd)
                    Button("Dismiss") { scope.act(.dismissSuggestion) }
                }
            }
        }
        .sheet(isPresented: $editing) {
            TextSheet(title: "Suggested note for ## \(card.section)", initial: card.note,
                      hint: "Done puts this on the card; Add there writes it to memory.md.") { text in
                scope.client.updateSuggestion(text, on: scope.messageID, in: scope.conversationID)
            }
        }
    }
}

// MARK: - Add to note

struct NotesCardView: View {
    var card: NotesCard
    var scope: CardScope
    @State private var editing = false
    @State private var picking = false

    var body: some View {
        CardBox {
            CardHeader(title: "Add to note",
                       detail: [card.subject.isEmpty ? nil : card.subject, card.sender.map { "from \($0)" }]
                           .compactMap { $0 }.joined(separator: " · "))
            Divider()
            CardBody {
                switch card.stage {
                case .choosing:
                    Secondary(card.candidates.isEmpty ? "No note stood out for this email. Pick one:"
                                                      : "Which note? The first is the best match.")
                    CandidateRows(candidates: card.candidates) { scope.act(.chooseNote($0)) }
                case .preview:
                    if let chosen = card.chosen { Text(chosen.title).appFont(.subheadline, weight: .semibold) }
                    Secondary("Goes under ## \(scope.info?.notesSection ?? "Correspondence")")
                    EntryBox(lines: card.entry.lines, heading: card.entry.heading)
                    if let duplicate = card.duplicate {
                        WarningText(duplicate.exact ? "This email is already in the note: \(duplicate.entry.heading)"
                                                    : "Looks like \(duplicate.entry.heading) already covers this.")
                    }
                case .inserted:
                    let title = card.chosen?.title ?? "the note"
                    DoneLine(text: Notes.withPlace(card.replaced == nil ? "Added to \(title)" : "Replaced in \(title)",
                                                   savedTo: card.savedTo))
                    if let notice = card.notice { NoticeLine(text: notice) }
                    if let written = card.written { EntryBox(lines: written.lines, heading: written.heading) }
                case .skipped:
                    Secondary("Skipped. Nothing was written.")
                case .undone:
                    Secondary("Undone: the entry was taken out of \(card.chosen?.title ?? "the note").")
                }
                if let problem = card.problem { WarningText(problem) }
            }
            switch card.stage {
            case .choosing:
                CardActions {
                    Button("None of these…") { picking = true }
                    Button("Skip") { scope.act(.skipNote) }
                }
            case .preview:
                CardActions {
                    Button("Edit…") { editing = true }
                    if card.duplicate != nil {
                        Button("Insert anyway") { scope.act(.insertNote(replace: false)) }
                        Button("Replace") { scope.act(.insertNote(replace: true)) }
                    } else {
                        Button("Insert") { scope.act(.insertNote(replace: false)) }
                    }
                    Button("Change note") { scope.act(.backToChoices) }
                    Button("Skip") { scope.act(.skipNote) }
                }
            case .inserted:
                CardActions {
                    if let chosen = card.chosen { NoteButton(path: chosen.path, scope: scope) }
                    Button("Undo") { scope.act(.undoNote) }
                }
            default:
                EmptyView()
            }
        }
        .sheet(isPresented: $editing) {
            NoteEntrySheet(noteTitle: card.chosen?.title ?? "", heading: card.entry.heading, lines: card.entry.body) { heading, body in
                scope.client.editNoteEntry(heading: heading, body: body, on: scope.messageID, in: scope.conversationID)
            }
        }
        .sheet(isPresented: $picking) {
            NotePicker(title: "Add to which note?", showKind: false, load: { try await scope.client.vaultNotes() }) { note in
                scope.act(.chooseNote(note.asNotesCandidate))
            }
        }
    }
}

/// Edit… on an "Add to note" card. Done puts the changes on the card; Insert there writes the file.
private struct NoteEntrySheet: View {
    var noteTitle: String
    var onDone: (String, String) -> Void
    @State private var heading: String
    @State private var lines: String
    @Environment(\.dismiss) private var dismiss

    init(noteTitle: String, heading: String, lines: String, onDone: @escaping (String, String) -> Void) {
        self.noteTitle = noteTitle
        self.onDone = onDone
        _heading = State(initialValue: heading)
        _lines = State(initialValue: lines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Heading") {
                    TextField("### 261106: …", text: $heading).autocorrectionDisabled()
                }
                Section {
                    TextEditor(text: $lines).frame(minHeight: 180)
                } header: {
                    Text("Lines")
                } footer: {
                    Text("Done puts this on the card; Insert there writes it to the note.")
                }
            }
            .navigationTitle(noteTitle.isEmpty ? "Edit the entry" : "Entry for \(noteTitle)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(heading, lines)
                        dismiss()
                    }
                    .disabled(heading.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - Send to CRM

struct CRMCardView: View {
    var card: CRMCard
    var scope: CardScope
    @State private var editing = false
    @State private var picking = false

    private var editLabel: String { card.text.isEmpty ? "Write…" : "Edit…" }
    private var crmSection: String { scope.info?.crmSection ?? "CRM" }

    var body: some View {
        CardBox {
            HStack {
                Text("Send to CRM").appFont(.subheadline, weight: .semibold)
                Spacer()
                TeamVisible(text: "Visible to your team in the CRM")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            CardBody {
                switch card.stage {
                case .choosing:
                    if card.text.isEmpty { Secondary("No update written yet.") } else { Text(card.text).appFont(.subheadline) }
                    rewriting
                    Secondary(card.candidates.isEmpty ? "Which project or organisation? Pick one:"
                                                      : "Which project or organisation? The first is the best match.")
                    CandidateRows(candidates: card.candidates) { scope.act(.crmChoose($0)) }
                case .preview:
                    if let chosen = card.chosen { Text(chosen.title).appFont(.subheadline, weight: .semibold) }
                    Secondary(card.createsSection
                              ? "Creates ## \(crmSection) " + (card.createsBefore.map { "before ## \($0)" } ?? "at the end of the note")
                              : "Goes into ## \(crmSection), newest first")
                    EntryBox(lines: card.entry)
                    rewriting
                    if card.postedToday { WarningText("You already posted to this note today.") }
                case .posted:
                    DoneLine(text: Notes.withPlace("Posted to \(card.chosen?.title ?? "the note") (## \(crmSection))",
                                                   savedTo: card.savedTo))
                    if let notice = card.notice { NoticeLine(text: notice) }
                    EntryBox(lines: card.entry)
                    if let sync = card.syncStatus { Secondary(sync) }
                case .skipped:
                    Secondary("Skipped. Nothing was posted.")
                }
                if let problem = card.problem { WarningText(problem) }
            }
            switch card.stage {
            case .choosing:
                CardActions {
                    Button(editLabel) { editing = true }.disabled(card.rewriting)
                    Button("None of these…") { picking = true }
                    Button("Skip") { scope.act(.crmSkip) }
                }
            case .preview:
                CardActions {
                    Button(card.postedToday ? "Post anyway" : "Post") { scope.act(.crmPost) }
                        .disabled(card.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || card.rewriting)
                    Button(editLabel) { editing = true }.disabled(card.rewriting)
                    Button("Change note") { scope.act(.crmBack) }
                    Button("Skip") { scope.act(.crmSkip) }
                }
            case .posted:
                if let chosen = card.chosen {
                    CardActions { NoteButton(path: chosen.path, scope: scope) }
                }
            case .skipped:
                EmptyView()
            }
        }
        .sheet(isPresented: $editing) { CRMSheet(card: card, scope: scope) }
        .sheet(isPresented: $picking) {
            NotePicker(title: "Which project or organisation?", showKind: true, load: { try await scope.client.crmNotes() }) { note in
                scope.act(.crmChoose(note.asCRMCandidate))
            }
        }
    }

    @ViewBuilder
    private var rewriting: some View {
        if card.rewriting {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Secondary("Rewriting…")
            }
        } else if let by = card.rewrittenBy {
            Secondary("Rewritten by \(by)")
        }
    }
}

/// Write… / Edit… on a CRM card. What's typed stays here until Done. Rewrite professionally sends the
/// text and instructions; the rewrite streams in (read-only meanwhile), then can be edited again.
private struct CRMSheet: View {
    var card: CRMCard
    var scope: CardScope
    @State private var text: String
    @State private var instructions = ""
    @State private var rewriting: Bool
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    init(card: CRMCard, scope: CardScope) {
        self.card = card
        self.scope = scope
        _text = State(initialValue: card.text)
        _rewriting = State(initialValue: card.rewriting)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 180)
                        .disabled(rewriting)
                        .opacity(rewriting ? 0.6 : 1)
                } header: {
                    HStack {
                        Text("Update")
                        Spacer()
                        TeamVisible(text: "Visible to your team")
                    }
                }
                Section {
                    TextField("e.g. shorter, mention Monday", text: $instructions, axis: .vertical)
                        .lineLimit(1...3)
                        .disabled(rewriting)
                    Button {
                        rewriting = true
                        problem = nil
                        scope.act(.crmRewrite(text: text, instructions: instructions))
                    } label: {
                        HStack {
                            Text(rewriting ? "Rewriting…" : "Rewrite professionally")
                            if rewriting {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(rewriting || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let problem { WarningText(problem) }
                } header: {
                    Text("Instructions for the rewrite (optional)")
                } footer: {
                    Text("Your draft model rewrites it in full paragraphs, with nothing added. You can edit the result. "
                         + "Done puts this on the card; Post there writes it to the note.")
                }
            }
            .navigationTitle((card.chosen?.title ?? card.noteHint).map { "CRM update for \($0)" } ?? "CRM update")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        scope.client.setCRMText(text, on: scope.messageID, in: scope.conversationID)
                        dismiss()
                    }
                    .disabled(rewriting)
                }
            }
        }
        // Follow the card while a rewrite streams into it (as the Mac's sheet does).
        .onChange(of: card) {
            guard card.rewriting || rewriting else { return }
            text = card.text
            rewriting = card.rewriting
            problem = card.problem
        }
    }
}

// MARK: - Shared sheets

/// One text, edited in a sheet and kept here until Done.
private struct TextSheet: View {
    var title: String
    var hint: String
    var onDone: (String) -> Void
    @State private var text: String
    @Environment(\.dismiss) private var dismiss

    init(title: String, initial: String, hint: String, onDone: @escaping (String) -> Void) {
        self.title = title
        self.hint = hint
        self.onDone = onDone
        _text = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text).frame(minHeight: 140)
                } footer: {
                    Text(hint)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(text)
                        dismiss()
                    }
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

/// "None of these…": every note from the Mac, filtered as you type.
private struct NotePicker: View {
    var title: String
    var showKind: Bool
    var load: () async throws -> [NoteFile]
    var onPick: (NoteFile) -> Void

    @State private var filter = ""
    @State private var notes: [NoteFile]?
    @State private var problem: String?
    @Environment(\.dismiss) private var dismiss

    private var shown: [NoteFile] { (notes ?? []).filter { $0.matches(filter) } }

    var body: some View {
        NavigationStack {
            List {
                if let problem { WarningText(problem) }
                if notes == nil {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Loading the notes…").foregroundStyle(.secondary)
                    }
                } else if shown.isEmpty {
                    Text("No notes match.").foregroundStyle(.secondary)
                }
                ForEach(shown) { note in
                    Button {
                        onPick(note)
                        dismiss()
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                Text(note.path).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                            Spacer()
                            if showKind, let kind = note.kind { Text(kind).appFont(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    .tint(.primary)
                }
            }
            .searchable(text: $filter, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Part of a name, a related name or a person")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Back") { dismiss() } }
            }
            .task {
                do {
                    notes = try await load().sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                } catch {
                    problem = (error as? RemoteProblem)?.message ?? "Couldn't load the notes."
                    notes = []
                }
            }
        }
    }
}

// MARK: - Note card (/obsidian)

/// A note's Summary, CRM and Correspondence, read-only: pick the note, then read the newest entries
/// (Show all for more), ask for a catch-up, post a CRM update, or read it again.
struct NoteViewCardView: View {
    var card: NoteViewCard
    var scope: CardScope
    @State private var filter = ""

    var body: some View {
        CardBox {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(card.chosen?.title ?? card.query.map { "Notes matching “\($0)”" } ?? "Your notes")
                    .appFont(.subheadline, weight: .semibold)
                if card.stage == .showing, let kind = card.kind {
                    Text(kind).appFont(.caption2).foregroundStyle(kind == "project" ? StatusColors.connected : .accentColor)
                }
                Spacer()
                if card.stage == .showing, let readAt = card.readAt {
                    Secondary("read \(CardDates.time(readAt))")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            CardBody {
                if let problem = card.problem { WarningText(problem) }
                switch card.stage {
                case .choosing: choices
                case .showing: sections
                }
            }
            if card.stage == .showing {
                CardActions {
                    let writing = card.catchUp?.state == .writing
                    Button(card.catchUp == nil ? "Catch me up" : "Catch me up again") { scope.act(.noteViewCatchUp) }
                        .disabled(writing)
                    if card.canPostCRM, scope.info?.crmConfigured == true {
                        Button("Post CRM update") { scope.act(.noteViewPostCRM) }
                    }
                    Button("Refresh") { scope.act(.noteViewRefresh) }
                    if let chosen = card.chosen { NoteButton(path: chosen.path, scope: scope) }
                }
            }
        }
    }

    /// Which note: the matches (or every note), filtered as you type when there are many.
    @ViewBuilder
    private var choices: some View {
        let many = card.candidates.count > 8
        if many {
            TextField("Type part of a note's name", text: $filter)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
        }
        let words = filter.lowercased().split(separator: " ").map(String.init)
        let shown = many && !words.isEmpty
            ? card.candidates.filter { candidate in words.allSatisfy { candidate.title.lowercased().contains($0) } }
            : card.candidates
        VStack(alignment: .leading, spacing: 0) {
            ForEach(shown.prefix(40)) { candidate in
                Button {
                    scope.act(.noteViewChoose(candidate))
                } label: {
                    HStack {
                        Text(candidate.title).appFont(.subheadline).foregroundStyle(.tint)
                        Spacer()
                        if !candidate.reason.isEmpty { Secondary(candidate.reason).lineLimit(1) }
                    }
                    .padding(.vertical, 7)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        if shown.isEmpty { Secondary("No notes match.") }
    }

    @ViewBuilder
    private var sections: some View {
        if card.shows(.summary) {
            SectionTitle(title: "Summary")
            let expanded = card.expanded.contains(.summary)
            Text(card.summary.isEmpty ? "(no summary)" : card.summary)
                .appFont(.subheadline)
                .foregroundStyle(card.summary.isEmpty ? .secondary : .primary)
                .lineLimit(expanded ? nil : 6)
                .copyable(card.summary)
            if card.summary.components(separatedBy: "\n").count > 6 || card.summary.count > 500 {
                ShowMore(label: expanded ? "Show less" : "Show all") { scope.act(.noteViewExpand(.summary)) }
            }
        }
        if card.shows(.crm) {
            Entries(card: card, section: .crm, title: card.crmSection, entries: card.crm, empty: "No CRM updates yet.", scope: scope)
        }
        if card.shows(.correspondence) {
            Entries(card: card, section: .correspondence, title: card.correspondenceSection, entries: card.correspondence,
                    empty: "No correspondence yet.", scope: scope)
        }
        if let catchUp = card.catchUp {
            SectionTitle(title: "Catch-up")
            switch catchUp.state {
            case .failed(let reason):
                WarningText("Couldn't write it: \(reason)")
            case .writing, .done:
                if !catchUp.text.isEmpty { Text(catchUp.text).appFont(.subheadline).copyable(catchUp.text) }
                if catchUp.state == .writing {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small)
                        Secondary("Catching up with \(catchUp.by)…")
                    }
                } else if !catchUp.by.isEmpty {
                    Secondary("By \(catchUp.by)")
                }
            }
        }
    }
}

private struct SectionTitle: View {
    var title: String

    var body: some View {
        Text("## \(title)").appFont(.caption, weight: .semibold).foregroundStyle(.tint).padding(.top, 2)
    }
}

private struct ShowMore: View {
    var label: String
    var action: () -> Void

    var body: some View {
        Button(label, action: action).appFont(.caption, weight: .medium).buttonStyle(.borderless)
    }
}

/// A section's `###` entries, newest first: the newest five, or all of them.
private struct Entries: View {
    var card: NoteViewCard
    var section: NoteSection
    var title: String
    var entries: [NoteEntry]
    var empty: String
    var scope: CardScope

    var body: some View {
        SectionTitle(title: title)
        if entries.isEmpty {
            Secondary(empty)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(card.shown(section, entries).enumerated()), id: \.offset) { _, entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.heading.drop { $0 == "#" || $0 == " " }).appFont(.subheadline, weight: .semibold)
                        ForEach(Array(entry.lines.enumerated()), id: \.offset) { _, line in
                            Text(line).appFont(.caption)
                        }
                    }
                }
            }
            .copyable(card.shown(section, entries).map { ([String($0.heading.drop { $0 == "#" || $0 == " " })] + $0.lines).joined(separator: "\n") }
                .joined(separator: "\n\n"))
            if entries.count > NoteViewCard.recent {
                let all = card.expanded.contains(section)
                ShowMore(label: all ? "Show the newest \(NoteViewCard.recent)" : "Show all \(entries.count)") {
                    scope.act(.noteViewExpand(section))
                }
            }
        }
    }
}
