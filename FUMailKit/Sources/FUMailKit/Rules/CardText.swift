import Foundation

/// A card as plain text: what the chat shows until each card has its own view (milestones 4–7), and
/// what Copy and VoiceOver get after that. The same text as the Windows app's `CardText`.
public enum CardText {
    public static func describe(_ card: Card, timeZone: TimeZone = .current, now: Date = .now) -> String {
        var lines: [String] = []
        func add(_ line: String = "") { lines.append(line) }
        func problems(_ list: [String]) { for problem in list { add("⚠ \(problem)") } }

        switch card {
        case .emailList(let list):
            add(list.title)
            if list.items.isEmpty { add(list.emptyText) }
            for (index, item) in list.items.enumerated() {
                let unread = item.unread ? "● " : ""
                add("\(index + 1). \(unread)\(item.from?.display ?? "(unknown sender)") — \(subject(item.subject))  "
                    + when(item.received, timeZone))
            }
            if let remaining = list.remainingCount, remaining > 0 { add("(\(remaining) more)") }
            problems(list.problems)

        case .thread(let thread):
            add(subject(thread.subject))
            if thread.side == .summary, let summary = thread.summary {
                add(text(of: summary))
                break
            }
            for message in thread.newestFirst {
                add()
                add("\(message.from?.display ?? "(unknown sender)")  \(when(message.received, timeZone))")
                add(thread.isOpen(message) ? message.body.trimmingTrailing() : message.preview)
                if !message.attachments.isEmpty { add("📎 \(message.attachments.joined(separator: ", "))") }
            }

        case .draftList(let drafts):
            add("Drafts")
            if drafts.items.isEmpty { add("No drafts.") }
            for (index, draft) in drafts.items.enumerated() {
                add("\(index + 1). To \(Drafts.line(draft.to)) — \(subject(draft.subject))")
            }
            problems(drafts.problems)

        case .draft(let draft):
            add("Draft: \(subject(draft.subject))")
            add("To: \(Drafts.line(draft.to))")
            if !draft.cc.isEmpty { add("Cc: \(Drafts.line(draft.cc))") }
            add()
            add(draft.body.trimmingTrailing())

        case .events(let events):
            add(events.title)
            if events.events.isEmpty { add(events.emptyText) }
            for event in events.events {
                let time = event.allDay ? "all day" : when(event.start, timeZone)
                let place = event.location.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
                add("\(time)  \(event.title)\(place)".trimmingCharacters(in: .whitespaces))
            }
            problems(events.problems)

        case .tasks(let tasks):
            add(tasks.list.map { "Tasks: \($0)" } ?? "Tasks")
            if tasks.tasks.isEmpty { add("Nothing to do.") }
            let today = TaskDates.string(now, timeZone: timeZone)
            for (group, members) in TaskDates.grouped(tasks.tasks, today: today) {
                add(group.rawValue)
                for task in members {
                    let due = task.dueDate.map { "  (\(TaskDates.label($0, now: now, timeZone: timeZone)))" } ?? ""
                    add("\(task.completed ? "☑" : "☐") \(task.title)\(due)")
                }
            }
            problems(tasks.problems)

        case .taskDraft(let draft):
            let heading = switch draft.stage {
            case .created: "Task created"
            case .cancelled: "New task (cancelled)"
            case .editing: "New task"
            }
            add(heading)
            add(draft.title)
            if let due = draft.dueDate {
                add("Due \(TaskDates.label(due, now: now, timeZone: timeZone)) · \(draft.list)")
            } else if !draft.list.isEmpty {
                add(draft.list)
            }
            if let problem = draft.problem { add(problem) }

        case .taskChange(let change):
            add(change.task.title)
            let outcome = switch change.stage {
            case .done: "Done."
            case .cancelled: "Cancelled."
            case .confirming: change.question(now: now, timeZone: timeZone)
            }
            add(outcome)
            if let problem = change.problem { add(problem) }

        case .notes(let notes):
            add("Add to note: \(subject(notes.subject))")
            if let chosen = notes.chosen { add("→ \(chosen.title)") }
            add(notes.entry.text)
            if let problem = notes.problem { add(problem) }

        case .crm(let crm):
            add(crm.chosen.map { "CRM update → \($0.title)" } ?? "CRM update")
            add(crm.entry.isEmpty ? crm.text : crm.entry.joined(separator: "\n"))
            if crm.stage == .posted { add("Posted.") }
            if let problem = crm.problem { add(problem) }

        case .noteView(let view):
            guard view.stage == .showing, let chosen = view.chosen else {
                add(view.query.map { "Notes matching “\($0)”" } ?? "Notes")
                for candidate in view.candidates { add("• \(candidate.title)") }
                break
            }
            add(chosen.title)
            if let catchUp = view.catchUp { add(text(of: catchUp)) }
            if view.shows(.summary), !view.summary.isEmpty { add(view.summary) }
            for (section, title, entries) in [(NoteSection.crm, view.crmSection, view.crm),
                                              (.correspondence, view.correspondenceSection, view.correspondence)]
            where view.shows(section) && !entries.isEmpty {
                add()
                add(title)
                for entry in view.shown(section, entries) { add(entry.text) }
                if entries.count > NoteViewCard.recent, !view.expanded.contains(section) {
                    add("(\(entries.count - NoteViewCard.recent) older)")
                }
            }
            if let problem = view.problem { add(problem) }

        case .suggestedNote(let suggestion):
            add("Suggested note for \(suggestion.section)")
            add(suggestion.note)

        case .unsupported(let name):
            add("(A “\(name)” card this version can't show yet.)")
        }
        return lines.joined(separator: "\n").trimmingTrailing()
    }

    static func text(of summary: ThreadCard.Summary) -> String {
        switch summary.state {
        case .writing: summary.text.isEmpty ? "Summarising…" : summary.text
        case .failed(let reason): "Couldn't summarise: \(reason)"
        case .done: summary.text
        }
    }

    static func subject(_ subject: String) -> String { subject.isEmpty ? "(no subject)" : subject }

    /// "Mon 16 Nov 14:05" in this device's time zone; "" without a date.
    public static func when(_ date: Date?, _ timeZone: TimeZone = .current) -> String {
        guard let date else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "EEE d MMM HH:mm"
        return formatter.string(from: date)
    }
}

extension TaskChangeCard {
    /// What Confirm would do: "Mark it done?", "Move it to Fri 20 Nov?"…
    public func question(now: Date = .now, timeZone: TimeZone = .current) -> String {
        switch change {
        case .complete: "Mark it done?"
        case .reopen: "Mark it open again?"
        case .reschedule(let due?): "Move it to \(TaskDates.label(due, now: now, timeZone: timeZone))?"
        case .reschedule(nil): "Remove its due date?"
        }
    }
}

extension String {
    func trimmingTrailing() -> String {
        var text = Substring(self)
        while let last = text.last, last.isWhitespace { text = text.dropLast() }
        return String(text)
    }
}
