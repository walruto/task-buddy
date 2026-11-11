import AppKit
import Foundation
import TaskBuddyCore

enum QuickLauncherError: LocalizedError {
    case emptyQuery
    case notFound(String)
    case couldNotOpen(String)

    var errorDescription: String? {
        switch self {
        case .emptyQuery: "Type something first."
        case .notFound(let query): "I couldn't find \(query). Try the Search shortcut instead."
        case .couldNotOpen(let query): "I found \(query), but macOS couldn't open it."
        }
    }
}

struct QuickLauncherService {
    func perform(_ mode: QuickLauncherMode, query: String) async throws {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw QuickLauncherError.emptyQuery }

        if mode == .search {
            guard let url = QuickLauncherQuery.searchURL(for: query), NSWorkspace.shared.open(url) else {
                throw QuickLauncherError.couldNotOpen(query)
            }
            return
        }

        if let url = QuickLauncherQuery.websiteURL(for: query) {
            guard NSWorkspace.shared.open(url) else { throw QuickLauncherError.couldNotOpen(query) }
            return
        }

        let appURL = await Task.detached(priority: .userInitiated) {
            Self.findApplication(named: query)
        }.value
        guard let appURL else { throw QuickLauncherError.notFound(query) }
        do {
            _ = try await NSWorkspace.shared.openApplication(
                at: appURL,
                configuration: NSWorkspace.OpenConfiguration()
            )
        } catch {
            throw QuickLauncherError.couldNotOpen(query)
        }
    }

    private static func findApplication(named query: String) -> URL? {
        let wanted = QuickLauncherQuery.normalizedAppName(query)
        guard !wanted.isEmpty else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let roots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            home.appendingPathComponent("Applications", isDirectory: true)
        ]
        var matches: [(score: Int, length: Int, url: URL)] = []
        for root in roots where FileManager.default.fileExists(atPath: root.path) {
            guard let enumerator = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "app" {
                let name = QuickLauncherQuery.normalizedAppName(url.deletingPathExtension().lastPathComponent)
                let score: Int
                if name == wanted { score = 0 }
                else if name.hasPrefix(wanted) { score = 1 }
                else if name.contains(wanted) { score = 2 }
                else { continue }
                matches.append((score, name.count, url))
            }
        }
        return matches.sorted {
            $0.score == $1.score ? $0.length < $1.length : $0.score < $1.score
        }.first?.url
    }
}
