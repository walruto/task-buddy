import Carbon
import Foundation
import TaskBuddyCore

final class GlobalHotKeyController {
    private static let signature: OSType = 0x54425544 // TBUD
    private var eventHandler: EventHandlerRef?
    private var hotKeyRefs: [EventHotKeyRef?] = []
    private let action: (QuickLauncherMode) -> Void

    init(action: @escaping (QuickLauncherMode) -> Void) {
        self.action = action
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        InstallEventHandler(
            GetApplicationEventTarget(),
            Self.handleEvent,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
    }

    func registerDefaults() -> String? {
        let modifiers = UInt32(optionKey | shiftKey)
        let shortcuts: [(id: UInt32, key: UInt32, label: String)] = [
            (1, UInt32(kVK_Return), "⌥⇧Return"),
            (2, UInt32(kVK_Space), "⌥⇧Space")
        ]
        var failures: [String] = []
        for shortcut in shortcuts {
            var reference: EventHotKeyRef?
            let status = RegisterEventHotKey(
                shortcut.key,
                modifiers,
                EventHotKeyID(signature: Self.signature, id: shortcut.id),
                GetApplicationEventTarget(),
                0,
                &reference
            )
            if status == noErr { hotKeyRefs.append(reference) } else { failures.append(shortcut.label) }
        }
        return failures.isEmpty ? nil : "Shortcut unavailable: \(failures.joined(separator: ", ")). Another app may be using it."
    }

    deinit {
        for reference in hotKeyRefs.compactMap({ $0 }) {
            UnregisterEventHotKey(reference)
        }
        if let eventHandler { RemoveEventHandler(eventHandler) }
    }

    private func dispatch(id: UInt32) {
        guard let mode: QuickLauncherMode = id == 1 ? .search : id == 2 ? .open : nil else { return }
        DispatchQueue.main.async { [action] in action(mode) }
    }

    private static let handleEvent: EventHandlerUPP = { _, event, userData in
        guard let event, let userData else { return OSStatus(eventNotHandledErr) }
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == GlobalHotKeyController.signature else {
            return OSStatus(eventNotHandledErr)
        }
        Unmanaged<GlobalHotKeyController>.fromOpaque(userData).takeUnretainedValue().dispatch(id: hotKeyID.id)
        return noErr
    }
}
