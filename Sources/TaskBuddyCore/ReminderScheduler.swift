import Foundation
import UserNotifications

public enum ReminderCategory {
    public static let general = "TASK_BUDDY_GENERAL"
    public static let calendar = "TASK_BUDDY_CALENDAR"
    public static let open = "TASK_BUDDY_OPEN"
    public static let snooze = "TASK_BUDDY_SNOOZE"
}

public enum ReminderPlanner {
    public static func nextOccurrence(of time: ReminderTime, after date: Date = .now, calendar: Calendar = .current) -> Date? {
        calendar.nextDate(
            after: date,
            matching: time.dateComponents,
            matchingPolicy: .nextTime,
            repeatedTimePolicy: .first,
            direction: .forward
        )
    }

    public static func notificationID(prefix: String, date: Date, calendar: Calendar = .current) -> String {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        return "\(prefix)-\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)-\(components.hour ?? 0)-\(components.minute ?? 0)"
    }
}

public final class ReminderScheduler: @unchecked Sendable {
    private let center: UNUserNotificationCenter
    private let calendar: Calendar

    public init(center: UNUserNotificationCenter = .current(), calendar: Calendar = .current) {
        self.center = center
        self.calendar = calendar
    }

    @discardableResult
    public func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .badge])
    }

    public func registerActions() {
        let open = UNNotificationAction(identifier: ReminderCategory.open, title: "Open Buddy", options: [.foreground])
        let snooze = UNNotificationAction(identifier: ReminderCategory.snooze, title: "Snooze 1 Hour")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: ReminderCategory.general, actions: [open, snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: ReminderCategory.calendar, actions: [open, snooze], intentIdentifiers: [])
        ])
    }

    public func reschedule(snapshot: CachedSnapshot, preferences: AppPreferences, now: Date = .now) async throws {
        let pending = await center.pendingNotificationRequests()
        let managed = pending.map(\.identifier).filter {
            $0.hasPrefix("digest-") || $0.hasPrefix("nudge-") || $0.hasPrefix("event-")
        }
        center.removePendingNotificationRequests(withIdentifiers: managed)

        let dueTasks = snapshot.tasks.filter { $0.isDueToday(calendar: calendar, now: now) || $0.isOverdue(calendar: calendar, now: now) }
        let todayEvents = snapshot.events.filter { calendar.isDate($0.start, inSameDayAs: now) }

        if let digestDate = ReminderPlanner.nextOccurrence(of: preferences.digestTime, after: now, calendar: calendar) {
            let content = content(
                title: "Your day with Task Buddy",
                body: summary(tasks: dueTasks.count, events: todayEvents.count),
                category: ReminderCategory.general
            )
            try await add(content, at: digestDate, id: ReminderPlanner.notificationID(prefix: "digest", date: digestDate, calendar: calendar))
        }

        if !dueTasks.isEmpty {
            for time in [preferences.firstNudgeTime, preferences.secondNudgeTime].compactMap({ $0 }) {
                if let date = ReminderPlanner.nextOccurrence(of: time, after: now, calendar: calendar) {
                    let body = nudgeSummary(tasks: dueTasks.count)
                    try await add(content(title: "A gentle nudge", body: body, category: ReminderCategory.general), at: date,
                                  id: ReminderPlanner.notificationID(prefix: "nudge", date: date, calendar: calendar))
                }
            }
        }

        for event in snapshot.events where !event.isAllDay {
            let fireDate = event.start.addingTimeInterval(-10 * 60)
            guard fireDate > now else { continue }
            let formatter = DateFormatter()
            formatter.timeStyle = .short
            let body = "\(event.title) starts at \(formatter.string(from: event.start))."
            try await add(content(title: "Starting in 10 minutes", body: body, category: ReminderCategory.calendar), at: fireDate,
                          id: "event-\(event.id)-\(Int(fireDate.timeIntervalSince1970))")
        }
    }

    public func snooze(_ notification: UNNotification, for interval: TimeInterval = 3600) async throws {
        let copy = notification.request.content.mutableCopy() as! UNMutableNotificationContent
        let request = UNNotificationRequest(
            identifier: "snooze-\(UUID().uuidString)",
            content: copy,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: max(60, interval), repeats: false)
        )
        try await center.add(request)
    }

    private func content(title: String, body: String, category: String) -> UNMutableNotificationContent {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.categoryIdentifier = category
        content.sound = nil
        return content
    }

    private func add(_ content: UNNotificationContent, at date: Date, id: String) async throws {
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let request = UNNotificationRequest(identifier: id, content: content,
                                            trigger: UNCalendarNotificationTrigger(dateMatching: components, repeats: false))
        try await center.add(request)
    }

    private func summary(tasks: Int, events: Int) -> String {
        "\(tasks) due task\(tasks == 1 ? "" : "s") and \(events) event\(events == 1 ? "" : "s")."
    }

    private func nudgeSummary(tasks: Int) -> String {
        "\(tasks) task\(tasks == 1 ? "" : "s") still need\(tasks == 1 ? "s" : "") you."
    }
}
