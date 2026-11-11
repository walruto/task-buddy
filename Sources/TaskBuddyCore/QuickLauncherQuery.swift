import Foundation

public enum QuickLauncherMode: String, Sendable {
    case search
    case open
}

public enum QuickLauncherQuery {
    public static func searchURL(for query: String) -> URL? {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nil }
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [URLQueryItem(name: "q", value: query)]
        return components?.url
    }

    public static func websiteURL(for input: String) -> URL? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return nil }
        let key = input.lowercased().replacingOccurrences(of: " ", with: "")
        let common: [String: String] = [
            "google": "https://google.com",
            "gmail": "https://mail.google.com",
            "youtube": "https://youtube.com",
            "github": "https://github.com",
            "reddit": "https://reddit.com",
            "spotify": "https://open.spotify.com"
        ]
        if let address = common[key] { return URL(string: address) }
        if input.hasPrefix("https://") || input.hasPrefix("http://") { return URL(string: input) }
        if !input.contains(" "), input.contains(".") { return URL(string: "https://\(input)") }
        return nil
    }

    public static func normalizedAppName(_ value: String) -> String {
        let name = value.lowercased().hasSuffix(".app") ? String(value.dropLast(4)) : value
        return name
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}
