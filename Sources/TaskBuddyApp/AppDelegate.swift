import AppKit
import Combine
import Network
import SwiftUI
import TaskBuddyCore
import UserNotifications

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let model = AppModel.shared
    private var panelController: PetPanelController!
    private var windows: AppWindowCoordinator!
    private var statusItem: NSStatusItem?
    private var hotKeys: GlobalHotKeyController?
    private let networkMonitor = NWPathMonitor()
    private var hadNetwork = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        windows = AppWindowCoordinator(model: model)
        panelController = PetPanelController(model: model, showControlCenter: { [weak self] in self?.windows.showControlCenter() })
        panelController.show()
        installStatusItem()
        hotKeys = GlobalHotKeyController { [weak self] mode in
            Task { @MainActor [weak self] in
                self?.panelController.showLauncher(mode)
            }
        }
        model.setLauncherShortcutError(hotKeys?.registerDefaults())

        UNUserNotificationCenter.current().delegate = self
        model.scheduler.registerActions()

        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(didChangeSpace),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
        networkMonitor.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in
                guard let self else { return }
                let restored = path.status == .satisfied && !self.hadNetwork
                self.hadNetwork = path.status == .satisfied
                if restored { await self.model.sync() }
            }
        }
        networkMonitor.start(queue: DispatchQueue(label: "TaskBuddy.NetworkMonitor"))

        if model.preferences.onboardingComplete {
            model.start()
            windows.showControlCenter()
        } else {
            windows.showOnboarding()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        model.stop()
        networkMonitor.cancel()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if model.preferences.onboardingComplete {
            windows.showControlCenter()
        } else {
            windows.showOnboarding()
        }
        return true
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        guard urls.contains(where: model.acceptSupabaseRecoveryURL) else { return }
        windows.showControlCenter()
    }

    @objc private func didWake() {
        Task { await model.sync() }
    }

    @objc private func didChangeSpace() {
        panelController.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            self?.panelController.show()
        }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            let image = Bundle.module.url(forResource: "BuddyMenuBar", withExtension: "svg").flatMap(NSImage.init(contentsOf:))
                ?? NSImage(systemSymbolName: "face.smiling.inverse", accessibilityDescription: "Task Buddy")
            image?.size = NSSize(width: 19, height: 19)
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "Task Buddy"
            button.setAccessibilityLabel("Task Buddy menu")
        }

        let menu = NSMenu(title: "Task Buddy")
        menu.addItem(menuItem("Open Buddy", action: #selector(openBuddyFromMenu)))
        menu.addItem(menuItem("Buddy Control Center…", action: #selector(openControlCenterFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quick Search  ⌥⇧Return", action: #selector(quickSearchFromMenu)))
        menu.addItem(menuItem("Quick Open  ⌥⇧Space", action: #selector(quickOpenFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Sync Now", action: #selector(syncFromMenu)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Task Buddy", action: #selector(quitFromMenu)))
        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func openBuddyFromMenu() {
        panelController.show()
        panelController.openBubble()
    }

    @objc private func openControlCenterFromMenu() {
        windows.showControlCenter()
    }

    @objc private func syncFromMenu() {
        Task { await model.sync() }
    }

    @objc private func quickSearchFromMenu() {
        panelController.showLauncher(.search)
    }

    @objc private func quickOpenFromMenu() {
        panelController.showLauncher(.open)
    }

    @objc private func quitFromMenu() {
        NSApp.terminate(nil)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        Task { @MainActor in
            model.character.play(.alert, for: .seconds(1.8))
            panelController.show()
        }
        completionHandler([.banner, .list])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        Task { @MainActor in
            if response.actionIdentifier == ReminderCategory.snooze {
                try? await model.scheduler.snooze(response.notification)
            } else {
                panelController.show()
                panelController.openBubble()
            }
            completionHandler()
        }
    }
}

@MainActor
private final class AppWindowCoordinator: NSObject, NSWindowDelegate {
    private let model: AppModel
    private var onboardingWindow: NSWindow?
    private var controlCenterWindow: NSWindow?

    init(model: AppModel) { self.model = model }

    func showOnboarding() {
        if let onboardingWindow {
            onboardingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(model: model) { [weak self] in
            self?.onboardingWindow?.close()
            self?.onboardingWindow = nil
            self?.showControlCenter()
        }
        onboardingWindow = makeWindow(title: "Welcome to Task Buddy", size: NSSize(width: 520, height: 700), view: view)
        onboardingWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showControlCenter() {
        if controlCenterWindow == nil {
            controlCenterWindow = makeWindow(
                title: "Buddy Control Center",
                size: NSSize(width: 540, height: 700),
                view: BuddyControlCenterView(model: model)
            )
        }
        controlCenterWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow<V: View>(title: String, size: NSSize, view: V) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.contentView = NSHostingView(rootView: view)
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        return window
    }
}

@MainActor
private final class InteractivePetPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
private final class PetPanelController {
    private let model: AppModel
    private let panel: NSPanel
    private var dragOrigin: NSPoint?
    private var closedFrameBeforeOpening: NSRect?
    private var cancellables: Set<AnyCancellable> = []

    private var petScale: CGFloat { CGFloat(AppPreferences.clampedPetScale(model.preferences.petScale)) }
    private var closedSize: NSSize { NSSize(width: 220 * petScale + 12, height: 220 * petScale + 12) }
    private var openSize: NSSize {
        let bubbleHeight: CGFloat = model.launcherMode == nil ? 500 : 210
        return NSSize(width: 384 + 220 * petScale, height: max(bubbleHeight, 220 * petScale) + 12)
    }

    init(model: AppModel, showControlCenter: @escaping () -> Void) {
        self.model = model
        let initialScale = CGFloat(AppPreferences.clampedPetScale(model.preferences.petScale))
        let initialSize = NSSize(width: 220 * initialScale + 12, height: 220 * initialScale + 12)
        panel = InteractivePetPanel(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.becomesKeyOnlyIfNeeded = true
        panel.worksWhenModal = true
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        var behavior: NSWindow.CollectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        if #available(macOS 26.0, *) {
            behavior.insert(.canJoinAllApplications)
        }
        panel.collectionBehavior = behavior
        panel.level = .screenSaver
        panel.contentView = NSHostingView(rootView: PetRootView(
            model: model,
            toggleBubble: { [weak self] in self?.toggleBubble() },
            dragChanged: { [weak self] translation in self?.drag(translation) },
            dragEnded: { [weak self] in self?.endDrag() },
            showControlCenter: showControlCenter
        ))

        model.$preferences
            .map(\.petScale)
            .removeDuplicates()
            .dropFirst()
            .sink { [weak self] _ in self?.applyPetScale() }
            .store(in: &cancellables)

        restorePosition()
    }

    func show() {
        panel.orderFrontRegardless()
    }

    func openBubble() {
        guard !model.isBubbleOpen else { return }
        toggleBubble()
    }

    func showLauncher(_ mode: QuickLauncherMode) {
        model.presentLauncher(mode)
        if model.isBubbleOpen {
            if let buddyFrame = closedFrameBeforeOpening {
                panel.setFrame(
                    PetPanelPlacement.openFrame(
                        around: buddyFrame,
                        openSize: openSize,
                        side: model.bubbleOnRight ? .right : .left
                    ),
                    display: true
                )
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            toggleBubble()
        }
    }

    private func toggleBubble() {
        let opening = !model.isBubbleOpen
        if opening {
            let buddyFrame = panel.frame
            closedFrameBeforeOpening = buddyFrame
            let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? buddyFrame
            let side = PetPanelPlacement.bubbleSide(for: buddyFrame, openWidth: openSize.width, in: visible)
            model.bubbleOnRight = side == .right
            panel.setFrame(
                PetPanelPlacement.openFrame(around: buddyFrame, openSize: openSize, side: side),
                display: true
            )
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            withAnimation(.easeOut(duration: 0.08)) {
                model.isBubbleOpen = true
            }
        } else {
            model.dismissLauncher()
            model.isBubbleOpen = false
            if let buddyFrame = closedFrameBeforeOpening {
                panel.setFrame(buddyFrame, display: true)
            } else {
                resizePanel(to: closedSize, animated: false)
            }
            closedFrameBeforeOpening = nil
            panel.resignKey()
            panel.orderFrontRegardless()
        }
    }

    private func applyPetScale() {
        guard model.isBubbleOpen, var buddyFrame = closedFrameBeforeOpening else {
            resizePanel(to: closedSize, animated: false)
            return
        }
        buddyFrame.size = closedSize
        closedFrameBeforeOpening = buddyFrame
        panel.setFrame(
            PetPanelPlacement.openFrame(
                around: buddyFrame,
                openSize: openSize,
                side: model.bubbleOnRight ? .right : .left
            ),
            display: true
        )
    }

    private func resizePanel(to size: NSSize, animated: Bool) {
        let oldFrame = panel.frame
        let rightEdge = oldFrame.maxX
        let bottom = oldFrame.minY
        var newFrame = NSRect(x: rightEdge - size.width, y: bottom, width: size.width, height: size.height)
        if let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame {
            newFrame.origin.x = max(visible.minX, min(newFrame.origin.x, visible.maxX - newFrame.width))
            newFrame.origin.y = max(visible.minY, min(newFrame.origin.y, visible.maxY - newFrame.height))
        }
        panel.setFrame(newFrame, display: true, animate: animated)
    }

    private func drag(_ translation: CGSize) {
        if dragOrigin == nil { dragOrigin = panel.frame.origin }
        guard let dragOrigin else { return }
        panel.setFrameOrigin(NSPoint(x: dragOrigin.x + translation.width, y: dragOrigin.y - translation.height))
    }

    private func endDrag() {
        dragOrigin = nil
        var buddyFrame = currentBuddyFrame
        buddyFrame = clampedBuddyFrame(buddyFrame)
        if model.isBubbleOpen {
            closedFrameBeforeOpening = buddyFrame
            panel.setFrame(
                PetPanelPlacement.openFrame(
                    around: buddyFrame,
                    openSize: openSize,
                    side: model.bubbleOnRight ? .right : .left
                ),
                display: true
            )
        } else {
            panel.setFrame(buddyFrame, display: true)
        }
        UserDefaults.standard.set(buddyFrame.minX, forKey: "petX")
        UserDefaults.standard.set(buddyFrame.minY, forKey: "petY")
    }

    private func restorePosition() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: "petX") != nil, defaults.object(forKey: "petY") != nil {
            panel.setFrameOrigin(NSPoint(x: defaults.double(forKey: "petX"), y: defaults.double(forKey: "petY")))
            clampToVisibleScreen()
        } else if let visible = NSScreen.main?.visibleFrame {
            panel.setFrameOrigin(NSPoint(x: visible.maxX - closedSize.width - 18, y: visible.minY + 18))
        }
    }

    private func clampToVisibleScreen() {
        panel.setFrame(clampedBuddyFrame(panel.frame), display: true)
    }

    private var currentBuddyFrame: NSRect {
        guard model.isBubbleOpen else { return panel.frame }
        return PetPanelPlacement.buddyFrame(
            inside: panel.frame,
            closedSize: closedSize,
            side: model.bubbleOnRight ? .right : .left
        )
    }

    private func clampedBuddyFrame(_ frame: NSRect) -> NSRect {
        guard let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return frame }
        return NSRect(
            x: max(visible.minX, min(frame.minX, visible.maxX - frame.width)),
            y: max(visible.minY, min(frame.minY, visible.maxY - frame.height)),
            width: frame.width,
            height: frame.height
        )
    }
}
