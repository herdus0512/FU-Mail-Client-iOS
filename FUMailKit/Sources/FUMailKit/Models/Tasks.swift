import Foundation

// Copied from the Mac app (Sources/FUMailCore/Tasks/Tasks.swift): the cards and the dates. Keep in
// step with it. Google Tasks keeps dates only ("2026-11-20"), compared as text against today on this
// device.

/// One task, as gtask returns it.
public struct TaskItem: Codable, Sendable, Hashable, Identifiable {
    public var id: String
    public var title: String
    /// The task list it's in ("Inbox", "Urgent", "Later").
    public var list: String
    public var completed: Bool
    /// "2026-11-20".
    public var dueDate: String?
    public var notes: String
    public var link: String?

    public init(id: String, title: String, list: String, completed: Bool = false, dueDate: String? = nil,
                notes: String = "", link: String? = nil) {
        self.id = id
        self.title = title
        self.list = list
        self.completed = completed
        self.dueDate = dueDate
        self.notes = notes
        self.link = link
    }
}

/// `/tasks [list]`: open tasks, grouped by when they're due. Done ones stay (struck through, with
/// Undo) until the card is refreshed.
public struct TaskListCard: Codable, Sendable, Hashable {
    /// The list shown, or nil for every list.
    public var list: String?
    public var tasks: [TaskItem]
    /// The lists gtask allows, for the Edit sheet and new tasks.
    public var lists: [String]
    public var problems: [String]
    /// Tasks being changed right now (their buttons show progress).
    public var busy: [String] = []
    public var readAt: Date
}

/// A new task, checked before it's created: from /task, Add task on an email, or chat.
public struct TaskDraftCard: Codable, Sendable, Hashable {
    public enum Stage: String, Codable, Sendable { case editing, created, cancelled }

    public var title: String
    public var list: String
    public var dueDate: String?
    public var notes: String
    /// The lists to choose from (the first is the default).
    public var lists: [String]
    public var stage: Stage = .editing
    /// The `summary` model is suggesting a title (from an email).
    public var suggestingTitle = false
    public var titleBy: String?
    /// The task once created.
    public var created: TaskItem?
    public var problem: String?
}

/// A change asked for in chat ("mark the dentist task done"), waiting for Confirm.
public struct TaskChangeCard: Codable, Sendable, Hashable {
    public enum Change: Codable, Sendable, Hashable {
        case complete
        case reopen
        /// nil removes the due date.
        case reschedule(dueDate: String?)
    }

    public enum Stage: String, Codable, Sendable { case confirming, done, cancelled }

    public var task: TaskItem
    public var change: Change
    public var stage: Stage = .confirming
    public var problem: String?
}

public enum TaskDates {
    static func formatter(_ timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// "2026-11-14" for a day.
    public static func string(_ date: Date, timeZone: TimeZone = .current) -> String {
        formatter(timeZone).string(from: date)
    }

    public static func date(_ text: String, timeZone: TimeZone = .current) -> Date? {
        formatter(timeZone).date(from: text)
    }

    /// `days` after today.
    public static func inDays(_ days: Int, from now: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return string(calendar.date(byAdding: .day, value: days, to: now) ?? now, timeZone: timeZone)
    }

    /// Next Monday (a week's time when today is Monday).
    public static func nextMonday(from now: Date = .now, timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let weekday = calendar.component(.weekday, from: now)  // 1 Sunday … 7 Saturday; Monday is 2
        let days = (2 - weekday + 7) % 7 == 0 ? 7 : (2 - weekday + 7) % 7
        return inDays(days, from: now, timeZone: timeZone)
    }

    /// "Overdue", "Today", "Upcoming" or "No date", for grouping.
    public enum Group: String, CaseIterable, Sendable { case overdue = "Overdue", today = "Today", upcoming = "Upcoming", noDate = "No date" }

    public static func group(_ task: TaskItem, today: String) -> Group {
        guard let due = task.dueDate else { return .noDate }
        if due < today { return .overdue }
        return due == today ? .today : .upcoming
    }

    /// The tasks in their groups, each by due date (then title); groups with nothing are left out.
    public static func grouped(_ tasks: [TaskItem], today: String) -> [(Group, [TaskItem])] {
        Group.allCases.compactMap { group in
            let members = tasks.filter { self.group($0, today: today) == group }
                .sorted { ($0.dueDate ?? "9999", $0.title.lowercased()) < ($1.dueDate ?? "9999", $1.title.lowercased()) }
            return members.isEmpty ? nil : (group, members)
        }
    }

    /// "Fri 20 Nov" for a due date, "Today", "Tomorrow" or "Yesterday" when it's close.
    public static func label(_ due: String, now: Date = .now, timeZone: TimeZone = .current) -> String {
        let today = string(now, timeZone: timeZone)
        if due == today { return "Today" }
        if due == inDays(1, from: now, timeZone: timeZone) { return "Tomorrow" }
        if due == inDays(-1, from: now, timeZone: timeZone) { return "Yesterday" }
        guard let date = date(due, timeZone: timeZone) else { return due }
        let out = DateFormatter()
        out.locale = Locale(identifier: "en_AU")
        out.timeZone = timeZone
        out.dateFormat = "EEE d MMM"
        return out.string(from: date)
    }
}
