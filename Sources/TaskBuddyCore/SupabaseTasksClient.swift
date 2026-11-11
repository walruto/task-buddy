import Foundation

public enum SupabaseClientError: LocalizedError, Equatable {
    case notAuthenticated
    case invalidConfiguration
    case requestFailed(String)

    public var errorDescription: String? {
        switch self {
        case .notAuthenticated: "Sign in to Supabase again."
        case .invalidConfiguration: "Supabase is not configured in this build."
        case .requestFailed(let message): message
        }
    }
}

public actor SupabaseTasksClient {
    public static let listID = "supabase:buddy_tasks"

    private struct AuthResponse: Decodable {
        let accessToken: String
        let refreshToken: String
        let expiresIn: Double
    }

    private struct ErrorResponse: Decodable {
        let message: String?
        let msg: String?
        let errorDescription: String?
        let error: String?
    }

    private struct TaskRow: Codable {
        let id: UUID
        let title: String
        let notes: String?
        let dueDate: String?
    }

    private struct NewTask: Encodable {
        let title: String
        let dueDate: String?
        let notes: String?
    }

    private struct TaskMetadata: Codable {
        let dueTime: String?
        let category: String?
    }

    private struct CompletedTask: Encodable {
        let completed: Bool
    }

    private let configuration: SupabaseConfiguration
    private let urlSession: URLSession
    private var session: SupabaseSession?
    private var webSocket: URLSessionWebSocketTask?

    public init(
        configuration: SupabaseConfiguration,
        session: SupabaseSession? = nil,
        urlSession: URLSession = .shared
    ) {
        self.configuration = configuration
        self.session = session
        self.urlSession = urlSession
    }

    @discardableResult
    public func signIn(email: String, password: String) async throws -> SupabaseSession {
        let body = try JSONSerialization.data(withJSONObject: ["email": email, "password": password])
        let data = try await send(path: "auth/v1/token", query: [URLQueryItem(name: "grant_type", value: "password")], method: "POST", body: body)
        let newSession = try decodeSession(data)
        session = newSession
        return newSession
    }

    public func requestPasswordReset(email: String, redirectTo: URL) async throws {
        let body = try JSONSerialization.data(withJSONObject: ["email": email])
        _ = try await send(
            path: "auth/v1/recover",
            query: [URLQueryItem(name: "redirect_to", value: redirectTo.absoluteString)],
            method: "POST",
            body: body
        )
    }

    public func updatePassword(accessToken: String, newPassword: String) async throws {
        guard newPassword.count >= 8 else {
            throw SupabaseClientError.requestFailed("Use at least 8 characters for the new password.")
        }
        let body = try JSONSerialization.data(withJSONObject: ["password": newPassword])
        _ = try await send(path: "auth/v1/user", method: "PUT", body: body, accessToken: accessToken)
    }

    public func currentSession() -> SupabaseSession? { session }

    public func signOut() { session = nil }

    public func listenForTaskChanges(onChange: @escaping @Sendable () async -> Void) async {
        var retryDelay = 1
        while !Task.isCancelled {
            do {
                try await listenForTaskChangesOnce(onChange: onChange)
                retryDelay = 1
            } catch is CancellationError {
                break
            } catch {
                guard !Task.isCancelled else { break }
                try? await Task.sleep(for: .seconds(retryDelay))
                retryDelay = min(retryDelay * 2, 10)
            }
        }
    }

    public func stopRealtime() {
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
    }

    public func fetchOpenTasks() async throws -> [TaskItem] {
        let query = [
            URLQueryItem(name: "select", value: "id,title,notes,due_date"),
            URLQueryItem(name: "completed", value: "eq.false"),
            URLQueryItem(name: "order", value: "due_date.asc.nullslast,created_at.asc")
        ]
        let data = try await sendAuthenticated(path: "rest/v1/buddy_tasks", query: query, method: "GET")
        let rows = try decoder.decode([TaskRow].self, from: data)
        return rows.map { row in
            let metadata = row.notes.flatMap(Self.metadata(from:))
            return TaskItem(
                id: row.id.uuidString.lowercased(),
                listID: Self.listID,
                title: row.title,
                notes: row.notes,
                dueDate: row.dueDate.flatMap { Self.date(from: $0, time: metadata?.dueTime) },
                dueTime: metadata?.dueTime.flatMap(Self.reminderTime(from:)),
                category: metadata?.category
            )
        }
    }

    public func createTask(title: String, dueDate: Date?, dueTime: ReminderTime? = nil, category: String? = nil) async throws {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { throw LocalServiceError.invalidTaskTitle }
        let metadata = try encoder.encode(TaskMetadata(
            dueTime: dueTime.map(Self.timeString),
            category: category?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        ))
        let body = try encoder.encode(NewTask(
            title: cleanTitle,
            dueDate: dueDate.map(Self.dateString),
            notes: String(data: metadata, encoding: .utf8)
        ))
        _ = try await sendAuthenticated(path: "rest/v1/buddy_tasks", method: "POST", body: body)
    }

    public func complete(_ task: TaskItem) async throws {
        guard task.listID == Self.listID, UUID(uuidString: task.id) != nil else {
            throw SupabaseClientError.requestFailed("That synced task is invalid.")
        }
        let body = try encoder.encode(CompletedTask(completed: true))
        _ = try await sendAuthenticated(
            path: "rest/v1/buddy_tasks",
            query: [URLQueryItem(name: "id", value: "eq.\(task.id)")],
            method: "PATCH",
            body: body
        )
    }

    private func validAccessToken() async throws -> String {
        guard let session else { throw SupabaseClientError.notAuthenticated }
        if session.expiresAt.timeIntervalSinceNow > 60 { return session.accessToken }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        guard let session else { throw SupabaseClientError.notAuthenticated }
        let body = try JSONSerialization.data(withJSONObject: ["refresh_token": session.refreshToken])
        let data: Data
        do {
            data = try await send(
                path: "auth/v1/token",
                query: [URLQueryItem(name: "grant_type", value: "refresh_token")],
                method: "POST",
                body: body
            )
        } catch {
            self.session = nil
            throw error
        }
        let refreshed = try decodeSession(data)
        self.session = refreshed
        return refreshed.accessToken
    }

    private func sendAuthenticated(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil
    ) async throws -> Data {
        let token = try await validAccessToken()
        do {
            return try await send(path: path, query: query, method: method, body: body, accessToken: token)
        } catch SupabaseClientError.notAuthenticated {
            let refreshedToken = try await refreshAccessToken()
            return try await send(path: path, query: query, method: method, body: body, accessToken: refreshedToken)
        }
    }

    func realtimeJoinMessage(accessToken: String) throws -> Data {
        try JSONSerialization.data(withJSONObject: [
            "topic": "realtime:task-buddy",
            "event": "phx_join",
            "payload": [
                "config": [
                    "broadcast": ["ack": false, "self": false],
                    "presence": ["enabled": false],
                    "postgres_changes": [
                        ["event": "INSERT", "schema": "public", "table": "buddy_tasks"],
                        ["event": "UPDATE", "schema": "public", "table": "buddy_tasks"]
                    ]
                ],
                "access_token": accessToken
            ],
            "ref": "1",
            "join_ref": "1"
        ])
    }

    private func listenForTaskChangesOnce(onChange: @escaping @Sendable () async -> Void) async throws {
        let accessToken = try await validAccessToken()
        guard var components = URLComponents(url: configuration.projectURL, resolvingAgainstBaseURL: false) else {
            throw SupabaseClientError.invalidConfiguration
        }
        components.scheme = "wss"
        components.path = "/realtime/v1/websocket"
        components.queryItems = [
            URLQueryItem(name: "apikey", value: configuration.publishableKey),
            URLQueryItem(name: "vsn", value: "1.0.0")
        ]
        guard let url = components.url else { throw SupabaseClientError.invalidConfiguration }

        let socket = urlSession.webSocketTask(with: url)
        webSocket = socket
        socket.resume()
        defer {
            socket.cancel(with: .goingAway, reason: nil)
            if webSocket === socket { webSocket = nil }
        }

        let joinData = try realtimeJoinMessage(accessToken: accessToken)
        guard let joinText = String(data: joinData, encoding: .utf8) else {
            throw SupabaseClientError.requestFailed("Could not start live task sync.")
        }
        try await socket.send(.string(joinText))

        let heartbeat = Task {
            var ref = 2
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(25))
                guard !Task.isCancelled else { break }
                let payload: [String: Any] = [
                    "topic": "phoenix",
                    "event": "heartbeat",
                    "payload": [:],
                    "ref": String(ref)
                ]
                ref += 1
                guard let data = try? JSONSerialization.data(withJSONObject: payload),
                      let text = String(data: data, encoding: .utf8) else { continue }
                try? await socket.send(.string(text))
            }
        }
        defer { heartbeat.cancel() }

        while !Task.isCancelled {
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .string(let text): data = Data(text.utf8)
            case .data(let value): data = value
            @unknown default: continue
            }
            guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let event = object["event"] as? String else { continue }
            if event == "postgres_changes" {
                await onChange()
            } else if event == "phx_reply",
                      let payload = object["payload"] as? [String: Any],
                      payload["status"] as? String == "error" {
                throw SupabaseClientError.requestFailed("Live task sync could not subscribe.")
            } else if event == "phx_error" || event == "phx_close" {
                throw SupabaseClientError.requestFailed("Live task sync disconnected.")
            }
        }
        throw CancellationError()
    }

    private func decodeSession(_ data: Data) throws -> SupabaseSession {
        let response = try decoder.decode(AuthResponse.self, from: data)
        return SupabaseSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: .now.addingTimeInterval(response.expiresIn)
        )
    }

    private func send(
        path: String,
        query: [URLQueryItem] = [],
        method: String,
        body: Data? = nil,
        accessToken: String? = nil
    ) async throws -> Data {
        guard configuration.projectURL.scheme == "https",
              !configuration.publishableKey.isEmpty,
              var components = URLComponents(
                url: configuration.projectURL.appending(path: path),
                resolvingAgainstBaseURL: false
              ) else { throw SupabaseClientError.invalidConfiguration }
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else { throw SupabaseClientError.invalidConfiguration }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 30
        request.setValue(configuration.publishableKey, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let accessToken { request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization") }
        if path.hasPrefix("rest/") && (method == "POST" || method == "PATCH") {
            request.setValue("return=minimal", forHTTPHeaderField: "Prefer")
        }

        let (data, response) = try await urlSession.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SupabaseClientError.requestFailed("Supabase returned an invalid response.")
        }
        guard 200..<300 ~= response.statusCode else {
            let payload = try? decoder.decode(ErrorResponse.self, from: data)
            let reportedMessage = payload?.message ?? payload?.msg
            let reportedError = payload?.errorDescription ?? payload?.error
            let message = reportedMessage ?? reportedError ?? "Supabase request failed (\(response.statusCode))."
            if response.statusCode == 401 { throw SupabaseClientError.notAuthenticated }
            throw SupabaseClientError.requestFailed(message)
        }
        return data
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return encoder
    }

    private static func dateString(_ date: Date) -> String {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
    }

    private static func date(from value: String, time: String? = nil) -> Date? {
        let parts = value.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        let clock = time.flatMap(reminderTime(from:))
        return Calendar.current.date(from: DateComponents(
            year: parts[0], month: parts[1], day: parts[2],
            hour: clock?.hour, minute: clock?.minute
        ))
    }

    private static func reminderTime(from value: String) -> ReminderTime? {
        let parts = value.split(separator: ":").compactMap { Int($0) }
        guard parts.count >= 2 else { return nil }
        return ReminderTime(hour: parts[0], minute: parts[1])
    }

    private static func timeString(_ time: ReminderTime) -> String {
        String(format: "%02d:%02d:00", time.hour, time.minute)
    }

    private static func metadata(from notes: String) -> TaskMetadata? {
        guard let data = notes.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try? decoder.decode(TaskMetadata.self, from: data)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
