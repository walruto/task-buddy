import AppKit
import XCTest
@testable import TaskBuddyCore

final class ModelTests: XCTestCase {
    func testOldPreferencesDecodeWithMigrationDefaults() throws {
        let data = Data(#"{"onboardingComplete":true,"isPinned":true,"launchAtLogin":false,"digestTime":{"hour":9,"minute":0},"dismissedMailIDs":[]}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertTrue(preferences.onboardingComplete)
        XCTAssertEqual(preferences.petScale, 1.0)
        XCTAssertFalse(preferences.appleMailEnabled)
        XCTAssertEqual(preferences.supabaseEmail, "")
        XCTAssertEqual(preferences.dataSourceVersion, 1)
        XCTAssertNil(preferences.firstNudgeTime)
        XCTAssertNil(preferences.secondNudgeTime)
    }

    func testPetSizeIsClampedWhenPreferencesDecode() throws {
        let data = Data(#"{"petScale":4,"digestTime":{"hour":9,"minute":0}}"#.utf8)
        let preferences = try JSONDecoder().decode(AppPreferences.self, from: data)
        XCTAssertEqual(preferences.petScale, AppPreferences.petScaleRange.upperBound)
    }

    func testBubblePlacementKeepsBuddyAnchoredOnEitherSide() {
        let visible = CGRect(x: 0, y: 0, width: 1_200, height: 900)
        let openSize = CGSize(width: 600, height: 520)
        let closedSize = CGSize(width: 220, height: 220)

        let rightBuddy = CGRect(x: 950, y: 20, width: 220, height: 220)
        let leftOpen = PetPanelPlacement.openFrame(around: rightBuddy, openSize: openSize, side: .left)
        XCTAssertEqual(PetPanelPlacement.bubbleSide(for: rightBuddy, openWidth: openSize.width, in: visible), .left)
        XCTAssertEqual(PetPanelPlacement.buddyFrame(inside: leftOpen, closedSize: closedSize, side: .left), rightBuddy)

        let leftBuddy = CGRect(x: 20, y: 20, width: 220, height: 220)
        let rightOpen = PetPanelPlacement.openFrame(around: leftBuddy, openSize: openSize, side: .right)
        XCTAssertEqual(PetPanelPlacement.bubbleSide(for: leftBuddy, openWidth: openSize.width, in: visible), .right)
        XCTAssertEqual(PetPanelPlacement.buddyFrame(inside: rightOpen, closedSize: closedSize, side: .right), leftBuddy)

        let compactOpen = PetPanelPlacement.openFrame(
            around: rightBuddy,
            openSize: CGSize(width: 600, height: 232),
            side: .left
        )
        XCTAssertEqual(PetPanelPlacement.buddyFrame(inside: compactOpen, closedSize: closedSize, side: .left), rightBuddy)
    }

    func testPreferencesDoNotPersistGoogleOAuthConfiguration() throws {
        let encoded = try JSONEncoder().encode(AppPreferences())
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8)).lowercased()
        XCTAssertFalse(json.contains("oauth"))
        XCTAssertFalse(json.contains("clientid"))
        XCTAssertFalse(json.contains("clientsecret"))
        XCTAssertFalse(json.contains("refreshtoken"))
    }

    func testTaskClassifiesTodayAndOverdue() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 11, day: 3, hour: 10)))
        let today = TaskItem(id: "today", listID: "1", title: "Today", dueDate: now)
        let yesterday = TaskItem(id: "old", listID: "1", title: "Old", dueDate: calendar.date(byAdding: .day, value: -1, to: now))
        XCTAssertTrue(today.isDueToday(calendar: calendar, now: now))
        XCTAssertTrue(yesterday.isOverdue(calendar: calendar, now: now))
    }

    func testFocusTimeFormatsAndClampsCountdowns() {
        XCTAssertEqual(FocusTime.formatted(seconds: 25 * 60), "25:00")
        XCTAssertEqual(FocusTime.formatted(seconds: 61), "01:01")
        XCTAssertEqual(FocusTime.formatted(seconds: -3), "00:00")
        XCTAssertEqual(FocusTime.remaining(totalSeconds: 90, elapsed: 12.8), 78)
        XCTAssertEqual(FocusTime.remaining(totalSeconds: 10, elapsed: 20), 0)
    }

    func testFocusAttentionModesClassifyPracticalSignals() {
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: false),
                mode: .screen
            ),
            .faceMissing
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, yawRadians: 0.6),
                mode: .paper
            ),
            .headTurned
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, gazeAway: true),
                mode: .screen
            ),
            .gazeAway
        )
        XCTAssertNil(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, gazeAway: true),
                mode: .paper
            )
        )
        XCTAssertNil(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, gazeDown: true),
                mode: .paper
            )
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, phoneDetected: true),
                mode: .paper
            ),
            .phoneUse
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, gazeDown: true, handsTogether: true),
                mode: .paper
            ),
            .phoneUse
        )
        XCTAssertNil(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, gazeAway: true, gazeDown: true),
                mode: .hybrid
            )
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, phoneDetected: true),
                mode: .hybrid
            ),
            .phoneUse
        )
        XCTAssertEqual(
            FocusAttentionClassifier.distractionReason(
                for: FaceAttentionSignals(facePresent: true, eyesClosed: true),
                mode: .paper
            ),
            .eyesClosed
        )
    }

    func testFocusCalibrationLearnsNeutralWorkingAngle() {
        let samples = Array(repeating: 0.18, count: 29) + [0.62]
        let neutral = FocusPostureCalibration.neutralYaw(from: samples)
        XCTAssertEqual(neutral, 0.18, accuracy: 0.0001)
        XCTAssertEqual(FocusPostureCalibration.calibratedYaw(0.34, neutralYaw: neutral) ?? 0, 0.16, accuracy: 0.0001)
        XCTAssertNil(FocusPostureCalibration.calibratedYaw(nil, neutralYaw: neutral))
    }

    func testQuickLauncherBuildsSearchAndWebsiteURLs() throws {
        let search = try XCTUnwrap(QuickLauncherQuery.searchURL(for: "pixel art buddy"))
        XCTAssertEqual(URLComponents(url: search, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "pixel art buddy")
        XCTAssertEqual(QuickLauncherQuery.websiteURL(for: "gmail")?.host, "mail.google.com")
        XCTAssertEqual(QuickLauncherQuery.websiteURL(for: "example.com")?.absoluteString, "https://example.com")
        XCTAssertNil(QuickLauncherQuery.websiteURL(for: "not a website"))
        XCTAssertEqual(QuickLauncherQuery.normalizedAppName("Google Chrome.app"), "googlechrome")
    }

    func testMailItemDecodesCachedJSONShape() throws {
        let data = Data(#"{"id":"<one@example.com>","threadID":"<one@example.com>","subject":"Do this","sender":"Friend","receivedAt":"2026-11-03T18:00:00Z","webURL":"https://mail.google.com/"}"#.utf8)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let reminder = try decoder.decode(MailReminder.self, from: data)
        XCTAssertEqual(reminder.subject, "Do this")
        XCTAssertEqual(reminder.threadID, "<one@example.com>")
    }

    func testReminderPlannerCrossesDSTUsingLocalWallTime() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let beforeDST = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12)))
        let next = try XCTUnwrap(ReminderPlanner.nextOccurrence(of: ReminderTime(hour: 9, minute: 0), after: beforeDST, calendar: calendar))
        let values = calendar.dateComponents([.day, .hour, .minute], from: next)
        XCTAssertEqual(values.day, 8)
        XCTAssertEqual(values.hour, 9)
        XCTAssertEqual(values.minute, 0)
    }

    func testLegacyMigrationDeletesOnlyOldSourceFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try Data("old".utf8).write(to: directory.appendingPathComponent("snapshot.json"))
        try Data("old".utf8).write(to: directory.appendingPathComponent("GoogleOAuthConfig.json"))
        try Data("keep".utf8).write(to: directory.appendingPathComponent("preferences.json"))

        try AppStorageStore(directory: directory).clearLegacyGoogleData()

        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("snapshot.json").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("GoogleOAuthConfig.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("preferences.json").path))
    }

    func testSupabaseSessionUsesOwnerOnlyFilePermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = AppStorageStore(directory: directory)
        try storage.save(SupabaseSession(accessToken: "access", refreshToken: "refresh", expiresAt: .now))
        let attributes = try FileManager.default.attributesOfItem(atPath: directory.appendingPathComponent("supabase-session.json").path)
        XCTAssertEqual(attributes[.posixPermissions] as? NSNumber, NSNumber(value: 0o600))
    }
}

final class SupabaseTasksClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testRealtimeJoinUsesUserTokenAndOnlyTaskInsertUpdateEvents() async throws {
        let client = SupabaseTasksClient(
            configuration: SupabaseConfiguration(
                projectURL: URL(string: "https://example.supabase.co")!,
                publishableKey: "sb_publishable_test"
            )
        )

        let data = try await client.realtimeJoinMessage(accessToken: "user-jwt")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let payload = try XCTUnwrap(root["payload"] as? [String: Any])
        let config = try XCTUnwrap(payload["config"] as? [String: Any])
        let changes = try XCTUnwrap(config["postgres_changes"] as? [[String: String]])

        XCTAssertEqual(payload["access_token"] as? String, "user-jwt")
        XCTAssertEqual(Set(changes.compactMap { $0["event"] }), ["INSERT", "UPDATE"])
        XCTAssertTrue(changes.allSatisfy { $0["schema"] == "public" && $0["table"] == "buddy_tasks" })
    }

    func testFetchMapsOwnedTaskAndSendsPublicCredentials() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "apikey"), "sb_publishable_test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access")
            let body = Data(#"[{"id":"31b8a819-6d61-4cb1-bc13-bc824227db65","title":"Phone task","notes":"{\"due_time\":\"14:30:00\",\"category\":\"School\"}","due_date":"2026-11-04"}]"#.utf8)
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let client = SupabaseTasksClient(
            configuration: SupabaseConfiguration(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test"),
            session: SupabaseSession(accessToken: "access", refreshToken: "refresh", expiresAt: .now.addingTimeInterval(3600)),
            urlSession: session
        )

        let tasks = try await client.fetchOpenTasks()

        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].title, "Phone task")
        XCTAssertEqual(tasks[0].listID, SupabaseTasksClient.listID)
        XCTAssertNotNil(tasks[0].dueDate)
        XCTAssertEqual(tasks[0].dueTime, ReminderTime(hour: 14, minute: 30))
        XCTAssertEqual(tasks[0].category, "School")
    }

    func testExpiredSessionRefreshesBeforeFetchingTasks() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        var requestedPaths: [String] = []
        StubURLProtocol.handler = { request in
            requestedPaths.append(try XCTUnwrap(request.url?.path))
            if request.url?.path == "/auth/v1/token" {
                let body = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8)
                return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer new-access")
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        let client = SupabaseTasksClient(
            configuration: SupabaseConfiguration(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test"),
            session: SupabaseSession(accessToken: "old", refreshToken: "refresh", expiresAt: .distantPast),
            urlSession: session
        )

        _ = try await client.fetchOpenTasks()

        XCTAssertEqual(requestedPaths, ["/auth/v1/token", "/rest/v1/buddy_tasks"])
        let refreshedSession = await client.currentSession()
        XCTAssertEqual(refreshedSession?.accessToken, "new-access")
    }

    func testUnauthorizedTaskRequestRefreshesAndRetriesOnce() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var taskRequests = 0
        StubURLProtocol.handler = { request in
            if request.url?.path == "/auth/v1/token" {
                let body = Data(#"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600}"#.utf8)
                return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
            }
            taskRequests += 1
            let status = taskRequests == 1 ? 401 : 200
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), taskRequests == 1 ? "Bearer old-access" : "Bearer new-access")
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: status, httpVersion: nil, headerFields: nil)!, Data("[]".utf8))
        }
        let client = SupabaseTasksClient(
            configuration: SupabaseConfiguration(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test"),
            session: SupabaseSession(accessToken: "old-access", refreshToken: "refresh", expiresAt: .now.addingTimeInterval(3600)),
            urlSession: urlSession
        )

        _ = try await client.fetchOpenTasks()

        XCTAssertEqual(taskRequests, 2)
        let refreshedSession = await client.currentSession()
        XCTAssertEqual(refreshedSession?.refreshToken, "new-refresh")
    }

    func testPasswordResetRequestsEmailAndUpdatesPasswordWithRecoveryToken() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: configuration)
        var requests: [URLRequest] = []
        StubURLProtocol.handler = { request in
            requests.append(request)
            return (HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let client = SupabaseTasksClient(
            configuration: SupabaseConfiguration(projectURL: URL(string: "https://example.supabase.co")!, publishableKey: "sb_publishable_test"),
            urlSession: urlSession
        )

        try await client.requestPasswordReset(email: "buddy@example.com", redirectTo: URL(string: "taskbuddy://reset-password")!)
        try await client.updatePassword(accessToken: "recovery-token", newPassword: "new-password")

        XCTAssertEqual(requests.map { $0.url?.path }, ["/auth/v1/recover", "/auth/v1/user"])
        XCTAssertEqual(URLComponents(url: try XCTUnwrap(requests[0].url), resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "taskbuddy://reset-password")
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer recovery-token")
    }
}

private final class StubURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try XCTUnwrap(Self.handler)(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class AppleMailClientTests: XCTestCase {
    func testDecodesAppleMailRowsAndBuildsGmailLink() throws {
        let rows = NSAppleEventDescriptor.list()
        let row = NSAppleEventDescriptor.list()
        row.insert(NSAppleEventDescriptor(string: "42"), at: 1)
        row.insert(NSAppleEventDescriptor(string: "<mail@example.com>"), at: 2)
        row.insert(NSAppleEventDescriptor(string: "Hello"), at: 3)
        row.insert(NSAppleEventDescriptor(string: "Friend <friend@example.com>"), at: 4)
        row.insert(NSAppleEventDescriptor(date: Date(timeIntervalSince1970: 100)), at: 5)
        rows.insert(row, at: 1)

        let messages = AppleMailClient.decode(rows)

        XCTAssertEqual(messages.first?.id, "<mail@example.com>")
        XCTAssertEqual(messages.first?.subject, "Hello")
        let url = try XCTUnwrap(messages.first?.webURL)
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "mail.google.com")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.fragment, "search/rfc822msgid:<mail@example.com>")
    }

    func testAppleMailScriptCompiles() throws {
        let script = try XCTUnwrap(NSAppleScript(source: AppleMailClient.script(limit: 20)))
        var error: NSDictionary?
        XCTAssertTrue(script.compileAndReturnError(&error), String(describing: error))
    }
}

@MainActor
final class CharacterStateTests: XCTestCase {
    func testQuickTaskRejectsBlankTitleBeforeSaving() {
        let client = AppleEventKitClient()
        XCTAssertThrowsError(try client.createTask(title: "   ", dueDate: nil)) { error in
            XCTAssertEqual(error as? LocalServiceError, .invalidTaskTitle)
        }
    }

    func testHigherPriorityStateWinsAndReleasesCleanly() {
        let controller = CharacterStateController()
        controller.begin(.thinking)
        XCTAssertEqual(controller.state, .thinking)
        controller.begin(.alert)
        XCTAssertEqual(controller.state, .alert)
        controller.begin(.error)
        XCTAssertEqual(controller.state, .error)
        controller.end(.error)
        XCTAssertEqual(controller.state, .alert)
        controller.end(.alert)
        XCTAssertEqual(controller.state, .thinking)
        controller.end(.thinking)
        XCTAssertEqual(controller.state, .idle)
    }

    func testAngryFocusStateOutranksBackgroundSync() {
        let controller = CharacterStateController()
        controller.begin(.thinking)
        controller.begin(.locked)
        XCTAssertEqual(controller.state, .locked)
        controller.end(.locked)
        XCTAssertEqual(controller.state, .thinking)
    }
}

final class AssetTests: XCTestCase {
    func testCharacterFramesAreTransparentAndUniform() throws {
        let project = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = project.appendingPathComponent("Sources/TaskBuddyApp/Resources/Character")
        let names = CharacterState.allCases.flatMap { ["\($0.rawValue)-1", "\($0.rawValue)-2"] }
        for name in names {
            let data = try Data(contentsOf: directory.appendingPathComponent("\(name).png"))
            let image = try XCTUnwrap(NSBitmapImageRep(data: data), name)
            XCTAssertEqual(image.pixelsWide, 256, name)
            XCTAssertEqual(image.pixelsHigh, 256, name)
            XCTAssertTrue(image.hasAlpha, name)
            let alpha = try XCTUnwrap(image.colorAt(x: 0, y: 0)?.alphaComponent, name)
            XCTAssertEqual(alpha, CGFloat.zero, accuracy: 0.001, name)
        }
    }
}
