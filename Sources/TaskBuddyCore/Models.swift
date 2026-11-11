import Foundation

public struct TaskItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let listID: String
    public let title: String
    public let notes: String?
    public let dueDate: Date?
    public let dueTime: ReminderTime?
    public let category: String?
    public let webURL: URL?

    public init(id: String, listID: String, title: String, notes: String? = nil, dueDate: Date? = nil, dueTime: ReminderTime? = nil, category: String? = nil, webURL: URL? = nil) {
        self.id = id
        self.listID = listID
        self.title = title
        self.notes = notes
        self.dueDate = dueDate
        self.dueTime = dueTime
        self.category = category
        self.webURL = webURL
    }

    public func isDueToday(calendar: Calendar = .current, now: Date = .now) -> Bool {
        dueDate.map { calendar.isDate($0, inSameDayAs: now) } ?? false
    }

    public func isOverdue(calendar: Calendar = .current, now: Date = .now) -> Bool {
        guard let dueDate else { return false }
        if dueTime != nil { return dueDate < now }
        return calendar.startOfDay(for: dueDate) < calendar.startOfDay(for: now)
    }
}

public struct CalendarItem: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let title: String
    public let start: Date
    public let end: Date?
    public let isAllDay: Bool
    public let webURL: URL?

    public init(id: String, title: String, start: Date, end: Date? = nil, isAllDay: Bool = false, webURL: URL? = nil) {
        self.id = id
        self.title = title
        self.start = start
        self.end = end
        self.isAllDay = isAllDay
        self.webURL = webURL
    }
}

public struct MailReminder: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public let threadID: String
    public let subject: String
    public let sender: String
    public let receivedAt: Date?
    public let webURL: URL?

    public init(id: String, threadID: String, subject: String, sender: String, receivedAt: Date? = nil, webURL: URL? = nil) {
        self.id = id
        self.threadID = threadID
        self.subject = subject
        self.sender = sender
        self.receivedAt = receivedAt
        self.webURL = webURL
    }
}

public enum ReminderItem: Identifiable, Hashable, Sendable {
    case task(TaskItem)
    case event(CalendarItem)
    case mail(MailReminder)

    public var id: String {
        switch self {
        case .task(let item): "task:\(item.id)"
        case .event(let item): "event:\(item.id)"
        case .mail(let item): "mail:\(item.id)"
        }
    }
}

public struct ReminderTime: Codable, Hashable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(23, max(0, hour))
        self.minute = min(59, max(0, minute))
    }

    public var dateComponents: DateComponents { DateComponents(hour: hour, minute: minute) }
}

public struct AppPreferences: Codable, Equatable, Sendable {
    public static let petScaleRange = 0.50...2.00
    public static let currentDataSourceVersion = 2

    public var onboardingComplete = false
    public var launchAtLogin = true
    public var petScale = 1.0
    public var digestTime = ReminderTime(hour: 9, minute: 0)
    public var firstNudgeTime: ReminderTime? = ReminderTime(hour: 14, minute: 0)
    public var secondNudgeTime: ReminderTime? = ReminderTime(hour: 18, minute: 0)
    public var dismissedMailIDs: Set<String> = []
    public var appleMailEnabled = false
    public var supabaseEmail = ""
    public var dataSourceVersion = 1

    public init() {}

    public static func clampedPetScale(_ value: Double) -> Double {
        min(petScaleRange.upperBound, max(petScaleRange.lowerBound, value))
    }

    private enum CodingKeys: String, CodingKey {
        case onboardingComplete, launchAtLogin, petScale, digestTime
        case firstNudgeTime, secondNudgeTime, dismissedMailIDs, appleMailEnabled, supabaseEmail, dataSourceVersion
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        onboardingComplete = try values.decodeIfPresent(Bool.self, forKey: .onboardingComplete) ?? false
        launchAtLogin = try values.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? true
        petScale = Self.clampedPetScale(try values.decodeIfPresent(Double.self, forKey: .petScale) ?? 1.0)
        digestTime = try values.decodeIfPresent(ReminderTime.self, forKey: .digestTime) ?? ReminderTime(hour: 9, minute: 0)
        firstNudgeTime = try values.decodeIfPresent(ReminderTime.self, forKey: .firstNudgeTime)
        secondNudgeTime = try values.decodeIfPresent(ReminderTime.self, forKey: .secondNudgeTime)
        dismissedMailIDs = try values.decodeIfPresent(Set<String>.self, forKey: .dismissedMailIDs) ?? []
        appleMailEnabled = try values.decodeIfPresent(Bool.self, forKey: .appleMailEnabled) ?? false
        supabaseEmail = try values.decodeIfPresent(String.self, forKey: .supabaseEmail) ?? ""
        dataSourceVersion = try values.decodeIfPresent(Int.self, forKey: .dataSourceVersion) ?? 1
    }

    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(onboardingComplete, forKey: .onboardingComplete)
        try values.encode(launchAtLogin, forKey: .launchAtLogin)
        try values.encode(Self.clampedPetScale(petScale), forKey: .petScale)
        try values.encode(digestTime, forKey: .digestTime)
        try values.encodeIfPresent(firstNudgeTime, forKey: .firstNudgeTime)
        try values.encodeIfPresent(secondNudgeTime, forKey: .secondNudgeTime)
        try values.encode(dismissedMailIDs, forKey: .dismissedMailIDs)
        try values.encode(appleMailEnabled, forKey: .appleMailEnabled)
        try values.encode(supabaseEmail, forKey: .supabaseEmail)
        try values.encode(dataSourceVersion, forKey: .dataSourceVersion)
    }
}

public struct SupabaseConfiguration: Codable, Equatable, Sendable {
    public let projectURL: URL
    public let publishableKey: String

    public init(projectURL: URL, publishableKey: String) {
        self.projectURL = projectURL
        self.publishableKey = publishableKey
    }
}

public struct SupabaseSession: Codable, Equatable, Sendable {
    public let accessToken: String
    public let refreshToken: String
    public let expiresAt: Date

    public init(accessToken: String, refreshToken: String, expiresAt: Date) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
    }
}

public struct CachedSnapshot: Codable, Equatable, Sendable {
    public var tasks: [TaskItem]
    public var events: [CalendarItem]
    public var mail: [MailReminder]
    public var syncedAt: Date

    public init(tasks: [TaskItem] = [], events: [CalendarItem] = [], mail: [MailReminder] = [], syncedAt: Date = .now) {
        self.tasks = tasks
        self.events = events
        self.mail = mail
        self.syncedAt = syncedAt
    }
}
