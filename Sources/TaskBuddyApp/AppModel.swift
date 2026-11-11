import AppKit
import EventKit
import Foundation
import ServiceManagement
import TaskBuddyCore

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published private(set) var tasks: [TaskItem] = []
    @Published private(set) var events: [CalendarItem] = []
    @Published private(set) var mail: [MailReminder] = []
    @Published private(set) var lastSyncedAt: Date?
    @Published private(set) var isSyncing = false
    @Published private(set) var remindersState: SourceConnectionState = .notConfigured
    @Published private(set) var calendarState: SourceConnectionState = .notConfigured
    @Published private(set) var mailState: SourceConnectionState = .notConfigured
    @Published private(set) var supabaseState: SourceConnectionState = .notConfigured
    @Published var mailFieldError: String?
    @Published var supabasePassword = ""
    @Published var supabaseFieldError: String?
    @Published private(set) var isSupabasePasswordRecovery = false
    @Published private(set) var isSupabaseResettingPassword = false
    @Published var newSupabasePassword = ""
    @Published var confirmSupabasePassword = ""
    @Published var supabaseResetMessage: String?
    @Published private(set) var isAddingTask = false
    @Published var quickTaskError: String?
    @Published var errorMessage: String?
    @Published var isBubbleOpen = false
    @Published var bubbleOnRight = false
    @Published var launcherMode: QuickLauncherMode?
    @Published var launcherQuery = ""
    @Published private(set) var isLauncherLoading = false
    @Published private(set) var launcherShortcutError: String?
    @Published var launcherError: String?
    @Published var preferences: AppPreferences

    let character = CharacterStateController()
    let scheduler = ReminderScheduler()
    let focus = FocusSessionController()

    private let storage = AppStorageStore()
    private let eventKit = AppleEventKitClient()
    private let appleMail = AppleMailClient()
    private let quickLauncher = QuickLauncherService()
    private var supabaseClient: SupabaseTasksClient?
    private var reminderTasks: [TaskItem] = []
    private var supabaseTasks: [TaskItem] = []
    private var pollTask: Task<Void, Never>?
    private var realtimeTask: Task<Void, Never>?
    private var supabaseRecoveryAccessToken: String?

    private init() {
        preferences = storage.loadPreferences()
        if preferences.dataSourceVersion < AppPreferences.currentDataSourceVersion {
            try? storage.clearLegacyGoogleData()
            preferences.dataSourceVersion = AppPreferences.currentDataSourceVersion
            preferences.onboardingComplete = false
            try? storage.save(preferences)
        } else if let snapshot = storage.loadSnapshot() {
            reminderTasks = snapshot.tasks.filter { $0.listID != SupabaseTasksClient.listID }
            supabaseTasks = snapshot.tasks.filter { $0.listID == SupabaseTasksClient.listID }
            refreshCombinedTasks()
            events = snapshot.events
            mail = snapshot.mail
            lastSyncedAt = snapshot.syncedAt
        }

        if let configuration = Self.loadSupabaseConfiguration() {
            let session = storage.loadSupabaseSession()
            supabaseClient = SupabaseTasksClient(configuration: configuration, session: session)
            if session != nil { supabaseState = .connected }
        }
        mailState = preferences.appleMailEnabled ? .connected : .notConfigured
        refreshAppleStates()
        focus.onLockStateChanged = { [weak self] isDistracted in
            guard let self else { return }
            if isDistracted {
                character.begin(.locked)
            } else {
                character.end(.locked)
            }
        }
    }

    var isAppleMailConnected: Bool { preferences.appleMailEnabled && mailState == .connected }
    var hasSupabaseSession: Bool { supabaseState == .connected }
    var isSupabaseConfigured: Bool { supabaseClient != nil }
    var taskSourceAvailable: Bool { supabaseState == .connected || remindersState == .connected }

    func start() {
        scheduler.registerActions()
        refreshAppleStates()
        Task { await sync() }
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15 * 60))
                guard !Task.isCancelled else { break }
                await self?.sync()
            }
        }
        startSupabaseRealtime()
    }

    func stop() {
        dismissLauncher()
        focus.close()
        pollTask?.cancel()
        pollTask = nil
        realtimeTask?.cancel()
        realtimeTask = nil
        if let supabaseClient { Task { await supabaseClient.stopRealtime() } }
    }

    func presentLauncher(_ mode: QuickLauncherMode) {
        launcherMode = mode
        launcherQuery = ""
        launcherError = nil
    }

    func dismissLauncher() {
        launcherMode = nil
        launcherQuery = ""
        launcherError = nil
        if isLauncherLoading {
            isLauncherLoading = false
            character.end(.thinking)
        }
    }

    func setLauncherShortcutError(_ message: String?) {
        launcherShortcutError = message
    }

    func runQuickLauncher() async -> Bool {
        guard let launcherMode else { return false }
        let query = launcherQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            launcherError = "Type something first."
            return false
        }

        isLauncherLoading = true
        launcherError = nil
        character.begin(.thinking)
        defer {
            isLauncherLoading = false
            character.end(.thinking)
        }
        do {
            try await quickLauncher.perform(launcherMode, query: query)
            return true
        } catch {
            launcherError = error.localizedDescription
            character.play(.error, for: .seconds(1.4))
            return false
        }
    }

    func requestRemindersAccess() {
        remindersState = .requesting
        Task {
            do {
                remindersState = try await eventKit.requestRemindersAccess() ? .connected : .denied
                if remindersState == .connected { await sync() }
            } catch {
                remindersState = .failed(error.localizedDescription)
            }
        }
    }

    func requestCalendarAccess() {
        calendarState = .requesting
        Task {
            do {
                calendarState = try await eventKit.requestCalendarAccess() ? .connected : .denied
                if calendarState == .connected { await sync() }
            } catch {
                calendarState = .failed(error.localizedDescription)
            }
        }
    }

    func connectAppleMail() {
        mailFieldError = nil
        mailState = .requesting
        character.begin(.thinking)
        Task {
            do {
                mail = try await appleMail.fetchInbox()
                    .filter { !preferences.dismissedMailIDs.contains($0.id) }
                preferences.appleMailEnabled = true
                mailState = .connected
                savePreferences()
                saveAndSchedule()
                character.end(.error)
                character.play(.wave, for: .seconds(1.6))
            } catch {
                mailState = .failed(error.localizedDescription)
                mailFieldError = error.localizedDescription
                character.begin(.error)
            }
            character.end(.thinking)
        }
    }

    func disconnectAppleMail() {
        preferences.appleMailEnabled = false
        mailState = .notConfigured
        mailFieldError = nil
        mail = []
        savePreferences()
        saveAndSchedule()
    }

    func connectSupabase() {
        supabaseFieldError = nil
        let email = preferences.supabaseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains(".") else {
            supabaseFieldError = "Enter the email used by the phone app."
            return
        }
        guard !supabasePassword.isEmpty else {
            supabaseFieldError = "Enter your Supabase task password."
            return
        }
        guard let supabaseClient else {
            supabaseFieldError = "Supabase configuration is missing from this build."
            return
        }

        supabaseState = .requesting
        character.begin(.thinking)
        Task {
            do {
                let session = try await supabaseClient.signIn(email: email, password: supabasePassword)
                try storage.save(session)
                supabaseTasks = try await supabaseClient.fetchOpenTasks()
                preferences.supabaseEmail = email
                supabasePassword = ""
                supabaseState = .connected
                refreshCombinedTasks()
                savePreferences()
                saveAndSchedule()
                startSupabaseRealtime()
                character.end(.error)
                character.play(.wave, for: .seconds(1.6))
            } catch {
                supabaseState = .failed(error.localizedDescription)
                supabaseFieldError = error.localizedDescription
                character.begin(.error)
            }
            character.end(.thinking)
        }
    }

    func requestSupabasePasswordReset() {
        supabaseFieldError = nil
        supabaseResetMessage = nil
        let email = preferences.supabaseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        guard email.contains("@"), email.contains(".") else {
            supabaseFieldError = "Enter the email used by the phone app."
            return
        }
        guard let supabaseClient, let redirectURL = URL(string: "taskbuddy://reset-password") else {
            supabaseFieldError = "Supabase configuration is missing from this build."
            return
        }

        isSupabaseResettingPassword = true
        Task {
            defer { isSupabaseResettingPassword = false }
            do {
                try await supabaseClient.requestPasswordReset(email: email, redirectTo: redirectURL)
                supabaseResetMessage = "Reset email sent. Open its link on this Mac or your Android phone."
                character.play(.wave, for: .seconds(1.6))
            } catch {
                supabaseFieldError = error.localizedDescription
                character.begin(.error)
            }
        }
    }

    @discardableResult
    func acceptSupabaseRecoveryURL(_ url: URL) -> Bool {
        guard url.scheme == "taskbuddy", url.host == "reset-password",
              let fragment = url.fragment,
              let items = URLComponents(string: "https://taskbuddy.local/?\(fragment)")?.queryItems,
              items.first(where: { $0.name == "type" })?.value == "recovery",
              let accessToken = items.first(where: { $0.name == "access_token" })?.value,
              !accessToken.isEmpty else { return false }
        supabaseRecoveryAccessToken = accessToken
        isSupabasePasswordRecovery = true
        supabaseFieldError = nil
        supabaseResetMessage = "Choose a new password below."
        return true
    }

    func completeSupabasePasswordReset() {
        supabaseFieldError = nil
        guard newSupabasePassword.count >= 8 else {
            supabaseFieldError = "Use at least 8 characters for the new password."
            return
        }
        guard newSupabasePassword == confirmSupabasePassword else {
            supabaseFieldError = "The new passwords do not match."
            return
        }
        guard let supabaseClient, let accessToken = supabaseRecoveryAccessToken else {
            supabaseFieldError = "Open the newest reset link from your email and try again."
            return
        }

        let password = newSupabasePassword
        let email = preferences.supabaseEmail.trimmingCharacters(in: .whitespacesAndNewlines)
        isSupabaseResettingPassword = true
        character.begin(.thinking)
        Task {
            defer {
                isSupabaseResettingPassword = false
                character.end(.thinking)
            }
            do {
                try await supabaseClient.updatePassword(accessToken: accessToken, newPassword: password)
                let session = try await supabaseClient.signIn(email: email, password: password)
                try storage.save(session)
                supabaseTasks = try await supabaseClient.fetchOpenTasks()
                supabaseState = .connected
                supabasePassword = ""
                newSupabasePassword = ""
                confirmSupabasePassword = ""
                supabaseRecoveryAccessToken = nil
                isSupabasePasswordRecovery = false
                supabaseResetMessage = "Password changed. Phone sync is connected again."
                refreshCombinedTasks()
                saveAndSchedule()
                startSupabaseRealtime()
                character.end(.error)
                character.play(.happy, for: .seconds(1.8))
            } catch {
                supabaseFieldError = error.localizedDescription
                character.begin(.error)
            }
        }
    }

    func disconnectSupabase() {
        realtimeTask?.cancel()
        realtimeTask = nil
        if let supabaseClient {
            Task {
                await supabaseClient.stopRealtime()
                await supabaseClient.signOut()
            }
        }
        try? storage.clearSupabaseSession()
        supabaseState = .notConfigured
        supabasePassword = ""
        supabaseTasks = []
        refreshCombinedTasks()
        saveAndSchedule()
    }

    func sync() async {
        guard !isSyncing else { return }
        refreshAppleStates()
        isSyncing = true
        errorMessage = nil
        character.begin(.thinking)
        defer {
            isSyncing = false
            character.end(.thinking)
        }

        var failures: [Error] = []
        var attemptedSource = false

        if remindersState == .connected {
            attemptedSource = true
            do { reminderTasks = try await eventKit.fetchOpenReminders(); refreshCombinedTasks() }
            catch { failures.append(error); remindersState = state(for: error) }
        }
        if supabaseState == .connected, let supabaseClient {
            attemptedSource = true
            do {
                supabaseTasks = try await supabaseClient.fetchOpenTasks()
                if let session = await supabaseClient.currentSession() { try storage.save(session) }
                supabaseState = .connected
                refreshCombinedTasks()
            } catch {
                failures.append(error)
                if error as? SupabaseClientError == .notAuthenticated {
                    supabaseState = .failed(error.localizedDescription)
                }
            }
        }
        if calendarState == .connected {
            attemptedSource = true
            do { events = try eventKit.fetchTodayEvents() }
            catch { failures.append(error); calendarState = state(for: error) }
        }
        if preferences.appleMailEnabled {
            attemptedSource = true
            do {
                mail = try await appleMail.fetchInbox()
                    .filter { !preferences.dismissedMailIDs.contains($0.id) }
                mailState = .connected
                mailFieldError = nil
            } catch {
                failures.append(error)
                mailState = .failed(error.localizedDescription)
                mailFieldError = error.localizedDescription
            }
        }

        if attemptedSource {
            lastSyncedAt = .now
            saveAndSchedule()
        }
        if let error = failures.first {
            errorMessage = error.localizedDescription
            character.begin(.error)
        } else {
            character.end(.error)
        }
    }

    func complete(_ task: TaskItem) {
        if task.listID == SupabaseTasksClient.listID, let supabaseClient {
            Task {
                do {
                    try await supabaseClient.complete(task)
                    supabaseTasks.removeAll { $0.id == task.id }
                    if let session = await supabaseClient.currentSession() { try storage.save(session) }
                    refreshCombinedTasks()
                    character.play(.happy, for: .seconds(1.5))
                    saveAndSchedule()
                } catch {
                    errorMessage = error.localizedDescription
                    if error as? SupabaseClientError == .notAuthenticated { supabaseState = .failed(error.localizedDescription) }
                    character.begin(.error)
                }
            }
            return
        }
        do {
            try eventKit.complete(task)
            reminderTasks.removeAll { $0.id == task.id && $0.listID == task.listID }
            refreshCombinedTasks()
            character.play(.happy, for: .seconds(1.5))
            saveAndSchedule()
        } catch {
            errorMessage = error.localizedDescription
            character.begin(.error)
        }
    }

    @discardableResult
    func addTask(title: String, dueDate: Date?, dueTime: ReminderTime? = nil, category: String? = nil) async -> Bool {
        guard !isAddingTask else { return false }
        isAddingTask = true
        quickTaskError = nil
        defer { isAddingTask = false }
        do {
            if supabaseState == .connected, let supabaseClient {
                try await supabaseClient.createTask(title: title, dueDate: dueDate, dueTime: dueTime, category: category)
                supabaseTasks = try await supabaseClient.fetchOpenTasks()
                if let session = await supabaseClient.currentSession() { try storage.save(session) }
            } else {
                try eventKit.createTask(title: title, dueDate: dueDate, dueTime: dueTime, category: category)
                reminderTasks = try await eventKit.fetchOpenReminders()
            }
            refreshCombinedTasks()
            character.end(.error)
            character.play(.happy, for: .seconds(1.5))
            saveAndSchedule()
            return true
        } catch {
            quickTaskError = error.localizedDescription
            character.begin(.error)
            return false
        }
    }

    func dismiss(_ reminder: MailReminder) {
        preferences.dismissedMailIDs.insert(reminder.id)
        mail.removeAll { $0.id == reminder.id }
        savePreferences()
        saveAndSchedule()
    }

    func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    func finishOnboarding() {
        preferences.onboardingComplete = true
        savePreferences()
        start()
    }

    func savePreferences() {
        try? storage.save(preferences)
        Task { try? await scheduler.reschedule(snapshot: currentSnapshot(), preferences: preferences) }
    }

    func requestNotifications() async {
        do { _ = try await scheduler.requestAuthorization() }
        catch { errorMessage = error.localizedDescription }
    }

    func applyLaunchAtLogin() {
        do {
            if preferences.launchAtLogin {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = "Launch at login will work after Task Buddy is packaged and moved to Applications. \(error.localizedDescription)"
        }
    }

    private func refreshAppleStates() {
        remindersState = state(for: eventKit.remindersStatus)
        calendarState = state(for: eventKit.calendarStatus)
    }

    private func startSupabaseRealtime() {
        realtimeTask?.cancel()
        guard supabaseState == .connected, let supabaseClient else {
            realtimeTask = nil
            return
        }
        realtimeTask = Task { [weak self] in
            await supabaseClient.listenForTaskChanges { [weak self] in
                await self?.refreshSupabaseFromRealtime()
            }
        }
    }

    private func refreshSupabaseFromRealtime() async {
        guard supabaseState == .connected, let supabaseClient else { return }
        do {
            supabaseTasks = try await supabaseClient.fetchOpenTasks()
            if let session = await supabaseClient.currentSession() { try storage.save(session) }
            lastSyncedAt = .now
            refreshCombinedTasks()
            saveAndSchedule()
            character.end(.error)
            character.play(.happy, for: .seconds(1.2))
        } catch {
            if error as? SupabaseClientError == .notAuthenticated {
                supabaseState = .failed(error.localizedDescription)
                errorMessage = error.localizedDescription
                character.begin(.error)
            }
        }
    }

    private func state(for status: EKAuthorizationStatus) -> SourceConnectionState {
        switch status {
        case .fullAccess: .connected
        case .denied, .restricted: .denied
        case .notDetermined, .writeOnly: .notConfigured
        @unknown default: .notConfigured
        }
    }

    private func state(for error: Error) -> SourceConnectionState {
        if error as? LocalServiceError == .remindersDenied || error as? LocalServiceError == .calendarDenied { return .denied }
        return .failed(error.localizedDescription)
    }

    private func saveAndSchedule() {
        let snapshot = currentSnapshot()
        try? storage.save(snapshot)
        Task { try? await scheduler.reschedule(snapshot: snapshot, preferences: preferences) }
    }

    private func currentSnapshot() -> CachedSnapshot {
        CachedSnapshot(tasks: tasks, events: events, mail: mail, syncedAt: lastSyncedAt ?? .now)
    }

    private func refreshCombinedTasks() {
        tasks = (supabaseTasks + reminderTasks).sorted {
            ($0.dueDate ?? .distantFuture, $0.title) < ($1.dueDate ?? .distantFuture, $1.title)
        }
    }

    private static func loadSupabaseConfiguration() -> SupabaseConfiguration? {
        guard let url = Bundle.module.url(forResource: "SupabaseConfig", withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SupabaseConfiguration.self, from: data)
    }
}
