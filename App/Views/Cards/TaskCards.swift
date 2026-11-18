import FUMailKit
import SwiftUI

// Google Tasks: the tasks card (/tasks), a new task waiting for Create (/task, Add task), and a
// change asked for in chat waiting for Confirm. Worded as the Mac's cards. Due dates are days
// ("2026-11-20"), compared with today on this device.

private func today() -> String { TaskDates.string(.now) }

// MARK: - Tasks card

struct TaskListCardView: View {
    var card: TaskListCard
    var scope: CardScope
    @State private var editing: TaskItem?

    var body: some View {
        CardBox {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.list.map { "Tasks · \($0)" } ?? "Tasks").appFont(.subheadline, weight: .semibold)
                    Text("\(card.openCount) open").appFont(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                if scope.busy {
                    ProgressView().controlSize(.small)
                } else {
                    Button { scope.act(.tasksRefresh) } label: { Image(systemName: "arrow.clockwise") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Read the tasks again")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            Divider()
            if card.tasks.isEmpty, card.problems.isEmpty {
                Text("No open tasks.").appFont(.footnote).foregroundStyle(.secondary).padding(12)
            }
            ForEach(TaskDates.grouped(card.tasks, today: today()), id: \.0) { group, tasks in
                Text(group.rawValue)
                    .appFont(.caption, weight: .semibold)
                    .foregroundStyle(group == .overdue ? AnyShapeStyle(StatusColors.failed) : AnyShapeStyle(.tint))
                    .padding(.horizontal, 12)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
                ForEach(tasks) { task in
                    TaskRow(task: task, working: card.busy.contains(task.id), overdue: group == .overdue, scope: scope) {
                        editing = task
                    }
                }
            }
            CardFooter(problems: card.problems)
        }
        .sheet(item: $editing) { task in
            TaskEditSheet(task: task) { title, due, notes in
                scope.act(.taskUpdate(taskID: task.id, title: title, notes: notes, dueDate: due))
            }
        }
    }
}

private struct TaskRow: View {
    var task: TaskItem
    var working: Bool
    var overdue: Bool
    var scope: CardScope
    var onEdit: () -> Void
    @State private var picking = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                scope.act(task.completed ? .taskReopen(taskID: task.id) : .taskComplete(taskID: task.id))
            } label: {
                Image(systemName: task.completed ? "checkmark.circle.fill" : "circle")
                    .appFont(.title3)
                    .foregroundStyle(task.completed ? StatusColors.connected : Color(.tertiaryLabel))
            }
            .buttonStyle(.borderless)
            .disabled(working)
            .accessibilityLabel(task.completed ? "Undo: mark it open again" : "Done")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .appFont(.subheadline)
                    .strikethrough(task.completed)
                    .foregroundStyle(task.completed ? .secondary : .primary)
                HStack(spacing: 0) {
                    Text(task.list)
                    if let due = task.dueDate {
                        Text(" · ")
                        Text(TaskDates.label(due))
                            .foregroundStyle(overdue && !task.completed ? AnyShapeStyle(StatusColors.failed) : AnyShapeStyle(.secondary))
                    }
                }
                .appFont(.caption)
                .foregroundStyle(.secondary)
                if let firstLine = task.notes.split(separator: "\n").first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
                    Text(firstLine).appFont(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                FlowLayout(spacing: 16) {
                    if working {
                        ProgressView().controlSize(.small)
                    } else if task.completed {
                        Button("Undo") { scope.act(.taskReopen(taskID: task.id)) }
                    } else {
                        Button("Done") { scope.act(.taskComplete(taskID: task.id)) }
                        Menu("Reschedule") {
                            Button("Today") { move(TaskDates.inDays(0)) }
                            Button("Tomorrow") { move(TaskDates.inDays(1)) }
                            Button("Next Monday") { move(TaskDates.nextMonday()) }
                            Button("In a week") { move(TaskDates.inDays(7)) }
                            Button("Pick a date…") { picking = true }
                            if task.dueDate != nil {
                                Button("No date", role: .destructive) { move(nil) }
                            }
                        }
                        Button("Edit", action: onEdit)
                    }
                    if !working, let link = task.link.flatMap(URL.init(string:)) {
                        Button("Open") { openURL(link) }
                    }
                }
                .buttonStyle(.borderless)
                .appFont(.subheadline)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(isPresented: $picking) {
            DuePickerSheet(current: task.dueDate) { move($0) }
        }
    }

    private func move(_ due: String?) {
        scope.act(.taskReschedule(taskID: task.id, dueDate: due))
    }
}

/// Edit on the tasks card: title, due date and details. The list can't be changed (gtask can't move tasks).
private struct TaskEditSheet: View {
    var task: TaskItem
    var onSave: (String, String?, String) -> Void
    @State private var title: String
    @State private var due: String?
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(task: TaskItem, onSave: @escaping (String, String?, String) -> Void) {
        self.task = task
        self.onSave = onSave
        _title = State(initialValue: task.title)
        _due = State(initialValue: task.dueDate)
        _notes = State(initialValue: task.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                } footer: {
                    Text("In \(task.list) (tasks can't be moved to another list)")
                }
                DueDateSection(due: $due)
                Section {
                    TextEditor(text: $notes).frame(minHeight: 120)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Save changes the task in Google Tasks.")
                }
            }
            .navigationTitle("Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.trimmingCharacters(in: .whitespaces), due, notes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }
}

// MARK: - New task

struct TaskDraftCardView: View {
    var card: TaskDraftCard
    var scope: CardScope
    @State private var editing = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 6) {
                Text("New task").appFont(.caption).foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Text(card.title.isEmpty ? "(no title yet)" : card.title).appFont(.subheadline, weight: .semibold)
                    if card.suggestingTitle { ProgressView().controlSize(.small) }
                }
                HStack(spacing: 14) {
                    Label(card.list, systemImage: "list.bullet")
                    Label(card.dueDate.map { TaskDates.label($0) } ?? "No due date", systemImage: "calendar")
                }
                .appFont(.caption)
                .foregroundStyle(.secondary)
                if !card.notes.isEmpty { Text(card.notes).appFont(.caption).foregroundStyle(.secondary) }
                if card.stage == .editing, let by = card.titleBy {
                    Text("Title suggested by \(by); change it with Edit…").appFont(.caption2).foregroundStyle(.secondary)
                }
                if let problem = card.problem { WarningText(problem) }
                switch card.stage {
                case .created:
                    Label("Created in \(card.created?.list ?? card.list)", systemImage: "checkmark.circle")
                        .appFont(.subheadline)
                        .foregroundStyle(StatusColors.connected)
                case .cancelled:
                    Text("Cancelled. Nothing was created.").appFont(.caption).foregroundStyle(.secondary)
                case .editing:
                    EmptyView()
                }
            }
            .padding(12)
            switch card.stage {
            case .editing:
                CardActions {
                    Button("Create") { scope.act(.taskCreate) }.disabled(!card.canCreate(busy: scope.busy))
                    Button("Edit…") { editing = true }.disabled(scope.busy)
                    Button("Cancel") { scope.act(.taskDraftCancel) }.disabled(scope.busy)
                    if scope.busy { ProgressView().controlSize(.small) }
                }
            case .created:
                if let link = card.created?.link.flatMap(URL.init(string:)) {
                    CardActions { Button("Open") { openURL(link) } }
                }
            case .cancelled:
                EmptyView()
            }
        }
        .sheet(isPresented: $editing) {
            TaskDraftSheet(card: card) { title, list, due, notes in
                scope.act(.taskDraftSet(title: title, list: list, dueDate: due, notes: notes))
            }
        }
    }
}

/// Edit… on a new task: everything stays here until Done, which sends it once (`task_draft_set`).
private struct TaskDraftSheet: View {
    var card: TaskDraftCard
    var onDone: (String, String, String?, String) -> Void
    @State private var title: String
    @State private var list: String
    @State private var due: String?
    @State private var notes: String
    @Environment(\.dismiss) private var dismiss

    init(card: TaskDraftCard, onDone: @escaping (String, String, String?, String) -> Void) {
        self.card = card
        self.onDone = onDone
        _title = State(initialValue: card.title)
        _list = State(initialValue: card.list)
        _due = State(initialValue: card.dueDate)
        _notes = State(initialValue: card.notes)
    }

    private var lists: [String] { card.lists.isEmpty ? [card.list] : card.lists }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title", text: $title)
                    Picker("List", selection: $list) {
                        ForEach(lists, id: \.self) { Text($0).tag($0) }
                    }
                }
                DueDateSection(due: $due)
                Section {
                    TextEditor(text: $notes).frame(minHeight: 120)
                } header: {
                    Text("Details")
                } footer: {
                    Text("Done puts this on the card; Create there makes the task.")
                }
            }
            .navigationTitle("New task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        onDone(title.trimmingCharacters(in: .whitespaces), list, due, notes)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || list.isEmpty)
                }
            }
        }
    }
}

// MARK: - A change from chat

struct TaskChangeCardView: View {
    var card: TaskChangeCard
    var scope: CardScope

    var body: some View {
        CardBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(card.task.title).appFont(.subheadline, weight: .semibold)
                if let due = card.task.dueDate {
                    Text("Due \(TaskDates.label(due))").appFont(.caption).foregroundStyle(.secondary)
                }
                if let problem = card.problem { WarningText(problem) }
                switch card.stage {
                case .confirming:
                    Text(card.question()).appFont(.subheadline)
                case .done:
                    Label("Done.", systemImage: "checkmark.circle").appFont(.subheadline).foregroundStyle(StatusColors.connected)
                case .cancelled:
                    Text("Cancelled. Nothing changed.").appFont(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(12)
            if card.stage == .confirming {
                CardActions {
                    Button("Confirm") { scope.act(.taskChangeConfirm) }.disabled(scope.busy)
                    Button("Cancel") { scope.act(.taskChangeCancel) }.disabled(scope.busy)
                    if scope.busy { ProgressView().controlSize(.small) }
                }
            }
        }
    }
}

// MARK: - Due dates

/// The due date in a form: a date, or none.
private struct DueDateSection: View {
    @Binding var due: String?

    var body: some View {
        Section("Due") {
            Toggle("Due date", isOn: Binding(get: { due != nil }, set: { on in
                due = on ? (due ?? TaskDates.inDays(1)) : nil
            }))
            if let current = due {
                DatePicker("Date", selection: Binding(get: { TaskDates.date(current) ?? .now },
                                                      set: { due = TaskDates.string($0) }),
                           displayedComponents: .date)
            }
        }
    }
}

/// Reschedule → Pick a date…
private struct DuePickerSheet: View {
    var onPick: (String) -> Void
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(current: String?, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        _date = State(initialValue: current.flatMap { TaskDates.date($0) } ?? .now)
    }

    var body: some View {
        NavigationStack {
            DatePicker("Due", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("Due date")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Move") {
                            onPick(TaskDates.string(date))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}
