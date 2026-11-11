import Foundation

public final class AppStorageStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let directory: URL
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    public init(fileManager: FileManager = .default, directory: URL? = nil) {
        self.fileManager = fileManager
        self.directory = directory ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TaskBuddy", isDirectory: true)
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    public func loadPreferences() -> AppPreferences {
        load(AppPreferences.self, from: "preferences.json") ?? AppPreferences()
    }

    public func save(_ preferences: AppPreferences) throws {
        try write(preferences, to: "preferences.json")
    }

    public func loadSnapshot() -> CachedSnapshot? {
        load(CachedSnapshot.self, from: "snapshot.json")
    }

    public func save(_ snapshot: CachedSnapshot) throws {
        try write(snapshot, to: "snapshot.json")
    }

    public func loadSupabaseSession() -> SupabaseSession? {
        load(SupabaseSession.self, from: "supabase-session.json")
    }

    public func save(_ session: SupabaseSession) throws {
        try write(session, to: "supabase-session.json")
        try fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: directory.appendingPathComponent("supabase-session.json").path
        )
    }

    public func clearSupabaseSession() throws {
        let url = directory.appendingPathComponent("supabase-session.json")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    public func clearLegacyGoogleData() throws {
        for name in ["snapshot.json", "GoogleOAuthConfig.json"] {
            let url = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
        }
    }

    private func load<T: Decodable>(_ type: T.Type, from name: String) -> T? {
        guard let data = try? Data(contentsOf: directory.appendingPathComponent(name)) else { return nil }
        return try? decoder.decode(type, from: data)
    }

    private func write<T: Encodable>(_ value: T, to name: String) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let destination = directory.appendingPathComponent(name)
        let temporary = directory.appendingPathComponent(".\(name).tmp")
        try encoder.encode(value).write(to: temporary, options: .atomic)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }
}
