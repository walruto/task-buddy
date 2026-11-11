import EventKit
import Foundation

public enum SourceConnectionState: Equatable, Sendable {
    case notConfigured
    case requesting
    case connected
    case denied
    case failed(String)
}

public enum LocalServiceError: LocalizedError, Equatable {
    case remindersDenied
    case calendarDenied
    case reminderNotFound
    case invalidTaskTitle
    case noReminderCalendar
    case appleMailUnavailable
    case appleMailAutomationDenied
    case appleMailFailed(String)

    public var errorDescription: String? {
        switch self {
        case .remindersDenied: "Allow Reminders access in System Settings → Privacy & Security → Reminders."
        case .calendarDenied: "Allow Calendar access in System Settings → Privacy & Security → Calendars."
        case .reminderNotFound: "That reminder no longer exists."
        case .invalidTaskTitle: "Enter a task name."
        case .noReminderCalendar: "Create a list in Apple Reminders, then try again."
        case .appleMailUnavailable: "Add an email account in Apple Mail, then try again."
        case .appleMailAutomationDenied: "Allow Task Buddy to control Mail in System Settings → Privacy & Security → Automation."
        case .appleMailFailed(let message): message
        }
    }
}

public struct AppleMailClient: Sendable {
    public init() {}

    public func fetchInbox(limit: Int = 20) async throws -> [MailReminder] {
        let safeLimit = min(100, max(1, limit))
        return try await Task.detached(priority: .utility) {
            guard let script = NSAppleScript(source: Self.script(limit: safeLimit)) else {
                throw LocalServiceError.appleMailFailed("Task Buddy could not prepare the Apple Mail connection.")
            }
            var scriptError: NSDictionary?
            let result = script.executeAndReturnError(&scriptError)
            if let scriptError {
                let number = (scriptError[NSAppleScript.errorNumber] as? NSNumber)?.intValue
                let message = scriptError[NSAppleScript.errorMessage] as? String ?? "Apple Mail could not be read."
                if number == -1743 { throw LocalServiceError.appleMailAutomationDenied }
                if number == 1001 { throw LocalServiceError.appleMailUnavailable }
                throw LocalServiceError.appleMailFailed(message)
            }
            return Self.decode(result)
        }.value
    }

    static func decode(_ descriptor: NSAppleEventDescriptor) -> [MailReminder] {
        guard descriptor.numberOfItems > 0 else { return [] }
        let messages: [MailReminder] = (1...descriptor.numberOfItems).compactMap { index -> MailReminder? in
            guard let row = descriptor.atIndex(index),
                  let localID = row.atIndex(1)?.stringValue else { return nil }
            let messageID = row.atIndex(2)?.stringValue ?? ""
            let stableID = messageID.isEmpty ? "apple-mail:\(localID)" : messageID
            let subject = row.atIndex(3)?.stringValue ?? "(No subject)"
            let sender = row.atIndex(4)?.stringValue ?? "Unknown sender"
            let receivedAt = row.atIndex(5)?.dateValue
            var gmailLink = URLComponents(string: "https://mail.google.com/mail/u/0/")
            gmailLink?.fragment = "search/rfc822msgid:\(messageID)"
            let url = messageID.isEmpty ? nil : gmailLink?.url
            return MailReminder(
                id: stableID,
                threadID: stableID,
                subject: subject,
                sender: sender,
                receivedAt: receivedAt,
                webURL: url
            )
        }
        return messages.sorted { ($0.receivedAt ?? .distantPast) > ($1.receivedAt ?? .distantPast) }
    }

    static func script(limit: Int) -> String {
        """
        tell application "Mail"
            if (count of accounts) is 0 then error "No Apple Mail accounts are configured." number 1001
            set inboxMessages to messages of inbox
            set takeCount to \(limit)
            if (count of inboxMessages) < takeCount then set takeCount to count of inboxMessages
            set resultRows to {}
            repeat with messageIndex from 1 to takeCount
                set currentMessage to item messageIndex of inboxMessages
                set localID to (id of currentMessage) as text
                set headerID to ""
                set messageSubject to "(No subject)"
                set messageSender to "Unknown sender"
                try
                    set headerID to («class meid» of currentMessage) as text
                end try
                try
                    set messageSubject to (subject of currentMessage) as text
                end try
                try
                    set messageSender to (sender of currentMessage) as text
                end try
                set receivedDate to «class rdrc» of currentMessage
                set end of resultRows to {localID, headerID, messageSubject, messageSender, receivedDate}
            end repeat
            return resultRows
        end tell
        """
    }
}

@MainActor
public final class AppleEventKitClient {
    private let store: EKEventStore
    private let calendar: Calendar

    public init(store: EKEventStore = EKEventStore(), calendar: Calendar = .current) {
        self.store = store
        self.calendar = calendar
    }

    public var remindersStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .reminder) }
    public var calendarStatus: EKAuthorizationStatus { EKEventStore.authorizationStatus(for: .event) }

    public func requestRemindersAccess() async throws -> Bool {
        try await store.requestFullAccessToReminders()
    }

    public func requestCalendarAccess() async throws -> Bool {
        try await store.requestFullAccessToEvents()
    }

    public func fetchOpenReminders() async throws -> [TaskItem] {
        guard remindersStatus == .fullAccess else { throw LocalServiceError.remindersDenied }
        let predicate = store.predicateForReminders(in: nil)
        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { continuation.resume(returning: $0 ?? []) }
        }
        return reminders.filter { !$0.isCompleted }.map { reminder in
            let dueComponents = reminder.dueDateComponents
            return TaskItem(
                id: reminder.calendarItemIdentifier,
                listID: reminder.calendar.calendarIdentifier,
                title: reminder.title,
                notes: reminder.notes,
                dueDate: dueComponents.flatMap { calendar.date(from: $0) },
                dueTime: dueComponents.flatMap { components in
                    guard let hour = components.hour else { return nil }
                    return ReminderTime(hour: hour, minute: components.minute ?? 0)
                },
                category: Self.category(from: reminder.notes),
                webURL: reminder.url
            )
        }
        .sorted { ($0.dueDate ?? .distantFuture, $0.title) < ($1.dueDate ?? .distantFuture, $1.title) }
    }

    public func fetchTodayEvents(now: Date = .now) throws -> [CalendarItem] {
        guard calendarStatus == .fullAccess else { throw LocalServiceError.calendarDenied }
        let start = calendar.startOfDay(for: now)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? now.addingTimeInterval(86_400)
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: nil)
        return store.events(matching: predicate)
            .filter { $0.status != .canceled }
            .map { event in
                CalendarItem(
                    id: event.calendarItemIdentifier,
                    title: event.title,
                    start: event.startDate,
                    end: event.endDate,
                    isAllDay: event.isAllDay,
                    webURL: event.url
                )
            }
            .sorted { $0.start < $1.start }
    }

    public func complete(_ task: TaskItem) throws {
        guard remindersStatus == .fullAccess else { throw LocalServiceError.remindersDenied }
        guard let reminder = store.calendarItem(withIdentifier: task.id) as? EKReminder else {
            throw LocalServiceError.reminderNotFound
        }
        reminder.isCompleted = true
        reminder.completionDate = .now
        try store.save(reminder, commit: true)
    }

    public func createTask(title: String, dueDate: Date?, dueTime: ReminderTime? = nil, category: String? = nil) throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw LocalServiceError.invalidTaskTitle }
        guard remindersStatus == .fullAccess else { throw LocalServiceError.remindersDenied }
        guard let reminderCalendar = store.defaultCalendarForNewReminders() else {
            throw LocalServiceError.noReminderCalendar
        }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = reminderCalendar
        reminder.title = cleanTitle
        if let category = category?.trimmingCharacters(in: .whitespacesAndNewlines), !category.isEmpty {
            reminder.notes = "Task Buddy category: \(category)"
        }
        if let dueDate {
            var components = calendar.dateComponents([.year, .month, .day], from: dueDate)
            components.hour = dueTime?.hour
            components.minute = dueTime?.minute
            components.calendar = calendar
            components.timeZone = calendar.timeZone
            reminder.dueDateComponents = components
        }
        try store.save(reminder, commit: true)
    }

    private static func category(from notes: String?) -> String? {
        let prefix = "Task Buddy category: "
        guard let line = notes?.split(separator: "\n").first(where: { $0.hasPrefix(prefix) }) else { return nil }
        return String(line.dropFirst(prefix.count))
    }
}
