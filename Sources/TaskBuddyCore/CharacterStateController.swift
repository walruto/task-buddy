import Foundation

public enum CharacterState: String, CaseIterable, Sendable {
    case idle, wave, thinking, locked, alert, error, happy

    var priority: Int {
        switch self {
        case .idle: 0
        case .wave: 1
        case .happy: 2
        case .thinking: 3
        case .locked: 4
        case .alert: 5
        case .error: 6
        }
    }
}

@MainActor
public final class CharacterStateController: ObservableObject {
    @Published public private(set) var state: CharacterState = .idle
    private var active: Set<CharacterState> = []
    private var expiryTasks: [CharacterState: Task<Void, Never>] = [:]

    public init() {}

    public func begin(_ newState: CharacterState) {
        expiryTasks[newState]?.cancel()
        active.insert(newState)
        updateState()
    }

    public func end(_ oldState: CharacterState) {
        expiryTasks[oldState]?.cancel()
        expiryTasks[oldState] = nil
        active.remove(oldState)
        updateState()
    }

    public func play(_ newState: CharacterState, for duration: Duration) {
        begin(newState)
        expiryTasks[newState] = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.end(newState)
        }
    }

    private func updateState() {
        state = active.max(by: { $0.priority < $1.priority }) ?? .idle
    }
}
