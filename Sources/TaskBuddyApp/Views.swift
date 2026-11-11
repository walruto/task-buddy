import AppKit
import SwiftUI
import TaskBuddyCore

private enum BuddyColors {
    static let ink = Color(red: 0.16, green: 0.13, blue: 0.24)
    static let cyan = Color(red: 0.76, green: 0.96, blue: 1.0)
    static let cyanDeep = Color(red: 0.15, green: 0.55, blue: 0.69)
    static let burgundy = Color(red: 0.34, green: 0.12, blue: 0.25)
    static let bubbleFill = Color(red: 0.90, green: 0.98, blue: 1.0)
    static let bubbleSurface = Color(red: 0.78, green: 0.95, blue: 0.99)
    static let bubbleMuted = Color(red: 0.34, green: 0.33, blue: 0.43)
}

private let buddyTaskCategories = ["Personal", "School", "Work", "Errands", "Health"]

struct PetRootView: View {
    @ObservedObject var model: AppModel
    @State private var isPressingBuddy = false
    let toggleBubble: () -> Void
    let dragChanged: (CGSize) -> Void
    let dragEnded: () -> Void
    let showControlCenter: () -> Void

    var body: some View {
        HStack(alignment: .bottom, spacing: 12) {
            if model.bubbleOnRight {
                buddyView
                if model.isBubbleOpen { bubbleView }
            } else {
                if model.isBubbleOpen { bubbleView }
                buddyView
            }
        }
        .frame(
            maxWidth: .infinity,
            maxHeight: .infinity,
            alignment: model.bubbleOnRight ? .bottomLeading : .bottomTrailing
        )
        .padding(6)
    }

    @ViewBuilder
    private var bubbleView: some View {
        Group {
            if model.launcherMode != nil {
                QuickLauncherBubble(model: model, close: toggleBubble)
                    .frame(width: 360, height: 210)
            } else {
                SpeechBubbleView(model: model, close: toggleBubble)
                    .frame(width: 360, height: 500)
            }
        }
        .transition(.opacity.combined(with: .scale(
            scale: 0.99,
            anchor: model.bubbleOnRight ? .bottomLeading : .bottomTrailing
        )))
    }

    private var buddyView: some View {
        VStack(spacing: 0) {
            if dueCount > 0 {
                Text("\(dueCount)")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(.red, in: Capsule())
                    .accessibilityLabel("\(dueCount) reminders need attention")
            }
            ZStack(alignment: .topLeading) {
                LiveCharacterSpriteView(character: model.character)
                BuddyInteractionView(
                    onPressed: { isPressingBuddy = $0 },
                    onClick: toggleBubble,
                    onDrag: dragChanged,
                    onDragEnd: dragEnded,
                    onSync: { Task { await model.sync() } },
                    onControlCenter: showControlCenter
                )
                .accessibilityHidden(true)
            }
                .frame(width: spriteSize, height: spriteSize)
                .overlay(alignment: .topLeading) {
                    FocusNudgeBubble(focus: model.focus)
                }
                .contentShape(Rectangle())
                .opacity(isPressingBuddy ? 0.88 : 1)
                .animation(.easeOut(duration: 0.06), value: isPressingBuddy)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Task Buddy")
                .accessibilityHint("Click to show your reminders. Drag to move.")
                .accessibilityAddTraits(.isButton)
        }
        .frame(width: petSize, height: petSize, alignment: .bottom)
    }

    private var dueCount: Int {
        model.tasks.filter { $0.isDueToday() || $0.isOverdue() }.count
    }

    private var scale: CGFloat { CGFloat(AppPreferences.clampedPetScale(model.preferences.petScale)) }
    private var petSize: CGFloat { 220 * scale }
    private var spriteSize: CGFloat { 200 * scale }
}

private struct LiveCharacterSpriteView: View {
    @ObservedObject var character: CharacterStateController

    var body: some View {
        CharacterSpriteView(state: character.state)
    }
}

private struct QuickLauncherBubble: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @FocusState private var queryFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text(mode == .search ? ">> QUICK SEARCH" : ">> QUICK OPEN")
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(BuddyColors.burgundy)
                Spacer()
                Text(mode == .search ? "⌥⇧RETURN" : "⌥⇧SPACE")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(BuddyColors.bubbleMuted)
                Button(action: dismiss) {
                    Text("X")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .frame(width: 26, height: 24)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(BuddyColors.burgundy)
                .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                .accessibilityLabel("Close quick launcher")
            }

            Text("WHAT SHOULD I OPEN, SIR?")
                .font(.system(size: 14, weight: .black, design: .monospaced))
                .foregroundStyle(BuddyColors.ink)

            TextField(mode == .search ? "SEARCH THE WEB..." : "APP OR WEBSITE...", text: $model.launcherQuery)
                .textFieldStyle(.plain)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundStyle(BuddyColors.ink)
                .padding(.horizontal, 10)
                .frame(height: 38)
                .background(.white.opacity(0.88))
                .overlay(Rectangle().stroke(queryFocused ? BuddyColors.cyanDeep : BuddyColors.ink, lineWidth: queryFocused ? 3 : 2))
                .focused($queryFocused)
                .disabled(model.isLauncherLoading)
                .onSubmit(run)
                .accessibilityLabel(mode == .search ? "Web search" : "App or website to open")

            HStack(spacing: 8) {
                if model.isLauncherLoading {
                    ProgressView().controlSize(.small).tint(BuddyColors.cyanDeep)
                    Text("OPENING...")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(BuddyColors.cyanDeep)
                } else if let error = model.launcherError {
                    Image(systemName: "exclamationmark.triangle.fill")
                    Text(error.uppercased()).lineLimit(2)
                } else {
                    Text(mode == .search ? "RETURN TO SEARCH • ESC TO CLOSE" : "RETURN TO OPEN • ESC TO CLOSE")
                }
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))
            .foregroundStyle(model.launcherError == nil ? BuddyColors.bubbleMuted : .red)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .padding(.bottom, 48)
        .background {
            PixelSpeechBubbleShape()
                .fill(BuddyColors.bubbleFill)
                .shadow(color: BuddyColors.ink.opacity(0.45), radius: 0, x: 6, y: 6)
        }
        .overlay(PixelSpeechBubbleShape().stroke(BuddyColors.ink, lineWidth: 5).allowsHitTesting(false))
        .overlay(alignment: .topTrailing) {
            PixelSparkles()
                .foregroundStyle(BuddyColors.cyanDeep)
                .padding(.top, 7)
                .padding(.trailing, 8)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
        .onAppear { DispatchQueue.main.async { queryFocused = true } }
        .onExitCommand(perform: dismiss)
    }

    private var mode: QuickLauncherMode { model.launcherMode ?? .open }

    private func run() {
        guard !model.isLauncherLoading else { return }
        Task {
            if await model.runQuickLauncher(), model.launcherMode != nil {
                model.dismissLauncher()
                close()
            }
        }
    }

    private func dismiss() {
        model.dismissLauncher()
        close()
    }
}

private struct BuddyInteractionView: NSViewRepresentable {
    let onPressed: (Bool) -> Void
    let onClick: () -> Void
    let onDrag: (CGSize) -> Void
    let onDragEnd: () -> Void
    let onSync: () -> Void
    let onControlCenter: () -> Void

    func makeNSView(context: Context) -> BuddyInteractionNSView {
        let view = BuddyInteractionNSView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ view: BuddyInteractionNSView, context: Context) {
        view.onPressed = onPressed
        view.onClick = onClick
        view.onDrag = onDrag
        view.onDragEnd = onDragEnd
        view.onSync = onSync
        view.onControlCenter = onControlCenter
    }
}

@MainActor
private final class BuddyInteractionNSView: NSView {
    var onPressed: (Bool) -> Void = { _ in }
    var onClick: () -> Void = {}
    var onDrag: (CGSize) -> Void = { _ in }
    var onDragEnd: () -> Void = {}
    var onSync: () -> Void = {}
    var onControlCenter: () -> Void = {}

    private var mouseDownPoint: NSPoint?
    private var didDrag = false
    private let dragThreshold: CGFloat = 10

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        mouseDownPoint = NSEvent.mouseLocation
        didDrag = false
        onPressed(true)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint else { return }
        let current = NSEvent.mouseLocation
        let dx = current.x - start.x
        let dy = current.y - start.y
        guard hypot(dx, dy) >= dragThreshold else { return }
        didDrag = true
        onPressed(false)
        onDrag(CGSize(width: dx, height: -dy))
    }

    override func mouseUp(with event: NSEvent) {
        onPressed(false)
        defer { mouseDownPoint = nil }
        if didDrag {
            onDragEnd()
        } else {
            onClick()
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu(title: "Task Buddy")
        let pinned = NSMenuItem(title: "Always Above Windows", action: nil, keyEquivalent: "")
        pinned.isEnabled = false
        menu.addItem(pinned)
        menu.addItem(menuItem("Sync Now", action: #selector(syncNow)))
        menu.addItem(menuItem("Buddy Control Center…", action: #selector(openControlCenter)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Quit Task Buddy", action: #selector(quit)))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    @objc private func syncNow() { onSync() }
    @objc private func openControlCenter() { onControlCenter() }
    @objc private func quit() { NSApp.terminate(nil) }
}

struct CharacterSpriteView: View {
    let state: CharacterState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var frame = 0

    var body: some View {
        Group {
            if let image = sprite(named: "\(state.rawValue)-\(frame + 1)") ?? sprite(named: "idle-1") {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.none)
                    .scaledToFit()
            } else {
                fallbackCharacter
            }
        }
        .scaleEffect(state == .alert && frame == 1 && !reduceMotion ? 1.035 : 1)
        .shadow(color: .black.opacity(0.15), radius: 2, y: 3)
        .task(id: "\(state.rawValue)-\(reduceMotion)") {
            frame = 0
            guard !reduceMotion else { return }
            while !Task.isCancelled {
                if state == .idle {
                    try? await Task.sleep(for: .seconds(Double.random(in: 3.0...5.5)))
                    guard !Task.isCancelled else { return }
                    frame = 1
                    try? await Task.sleep(for: .milliseconds(140))
                    frame = 0
                } else {
                    try? await Task.sleep(for: .milliseconds(frameDuration))
                    guard !Task.isCancelled else { return }
                    frame = frame == 0 ? 1 : 0
                }
            }
        }
    }

    private var frameDuration: Int {
        switch state {
        case .thinking, .error: 450
        case .locked: 240
        case .alert, .happy: 230
        case .wave: 320
        case .idle: 140
        }
    }

    private func sprite(named name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png", subdirectory: "Character")
            ?? Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }

    private var fallbackCharacter: some View {
        ZStack {
            Capsule().fill(BuddyColors.cyan).overlay(Capsule().stroke(BuddyColors.cyanDeep, lineWidth: 3))
            HStack(spacing: 28) {
                Circle().fill(BuddyColors.ink).frame(width: 13, height: 18)
                Circle().fill(BuddyColors.ink).frame(width: 13, height: 18)
            }
            .offset(y: -24)
            RoundedRectangle(cornerRadius: 2).fill(BuddyColors.ink).frame(width: 14, height: 4).offset(y: -10)
            Capsule().fill(BuddyColors.burgundy).frame(height: 44).offset(y: -78)
        }
        .padding(24)
    }
}

private struct FocusNudgeBubble: View {
    @ObservedObject var focus: FocusSessionController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var chunkIndex = 0

    private let chunks = ["LOCK IN.", "DO YOU WANT TO", "REGRET IT LATER?", "LOCK IN NOW."]

    var body: some View {
        Group {
            if focus.isRunning && focus.isNudgeVisible {
                ZStack {
                    PixelNudgeBubbleShape()
                        .fill(BuddyColors.bubbleFill)
                        .overlay(PixelNudgeBubbleShape().stroke(BuddyColors.burgundy, lineWidth: 3))
                        .shadow(color: BuddyColors.ink.opacity(0.35), radius: 0, x: 3, y: 3)
                    Text(reduceMotion ? "LOCK IN NOW.\nDON'T REGRET IT LATER." : chunks[chunkIndex])
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(BuddyColors.burgundy)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                        .padding(.horizontal, 8)
                        .padding(.bottom, 9)
                }
                .frame(width: 138, height: 58)
                .offset(x: -4, y: 2)
                .transition(.opacity)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Lock in. Do you want to regret it later, or lock in now?")
                .allowsHitTesting(false)
            }
        }
        .task(id: focus.isNudgeVisible) {
            chunkIndex = 0
            guard focus.isNudgeVisible, !reduceMotion else { return }
            while !Task.isCancelled && focus.isNudgeVisible {
                try? await Task.sleep(for: .milliseconds(900))
                guard !Task.isCancelled else { return }
                chunkIndex = (chunkIndex + 1) % chunks.count
            }
        }
    }
}

private struct PixelNudgeBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: 8, y: 2))
        path.addLine(to: CGPoint(x: rect.maxX - 8, y: 2))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: 8))
        path.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - 16))
        path.addLine(to: CGPoint(x: rect.maxX - 9, y: rect.maxY - 9))
        path.addLine(to: CGPoint(x: rect.maxX - 22, y: rect.maxY - 9))
        path.addLine(to: CGPoint(x: rect.maxX - 15, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.maxX - 34, y: rect.maxY - 9))
        path.addLine(to: CGPoint(x: 8, y: rect.maxY - 9))
        path.addLine(to: CGPoint(x: 2, y: rect.maxY - 15))
        path.addLine(to: CGPoint(x: 2, y: 8))
        path.closeSubpath()
        return path
    }
}

struct SpeechBubbleView: View {
    @ObservedObject var model: AppModel
    let close: () -> Void
    @State private var taskTitle = ""
    @State private var taskHasDueDate = false
    @State private var taskDueDate = Date()
    @State private var taskDueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var taskCategory = buddyTaskCategories[0]
    @State private var taskAdded = false
    @State private var showingFocus = false
    @State private var mailExpanded = false
    @FocusState private var taskTitleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(">> TASK BUDDY")
                        .font(.system(size: 13, weight: .black, design: .monospaced))
                        .foregroundStyle(BuddyColors.burgundy)
                    Text(greeting.uppercased())
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(BuddyColors.ink)
                }
                Spacer(minLength: 4)
                if model.isSyncing { ProgressView().controlSize(.small).tint(BuddyColors.cyanDeep) }
                Button {
                    if showingFocus {
                        showingFocus = false
                    } else {
                        if model.focus.selectedTaskID.isEmpty { model.focus.select(model.tasks.first) }
                        showingFocus = true
                    }
                } label: {
                    Image(systemName: showingFocus ? "list.bullet" : "lock.fill")
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(showingFocus ? BuddyColors.ink : .white)
                .background(showingFocus ? BuddyColors.bubbleSurface : BuddyColors.burgundy)
                .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                .help(showingFocus ? "Back to tasks" : "Lock In focus mode")
                .accessibilityLabel(showingFocus ? "Back to tasks" : "Open Lock In focus mode")
                Button { Task { await model.sync() } } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(BuddyColors.ink)
                .background(BuddyColors.bubbleSurface)
                .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                .help("Sync now")
                .accessibilityLabel("Sync now")
                Button {
                    close()
                } label: {
                    Text("X")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .frame(width: 28, height: 26)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(BuddyColors.burgundy)
                .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                .help("Close")
                .accessibilityLabel("Close task bubble")
            }

            Text(syncStatus)
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundStyle(BuddyColors.bubbleMuted)

            if showingFocus {
                LockInFocusView(model: model)
            } else {
                if let error = model.errorMessage {
                    StatusBanner(icon: "exclamationmark.triangle.fill", text: error, color: .red)
                }

                quickTaskEntry

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        taskSection
                        mailSection
                        eventSection
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .padding(.top, 18)
        .padding(.horizontal, 18)
        .padding(.bottom, 58)
        .background {
            PixelSpeechBubbleShape()
                .fill(BuddyColors.bubbleFill)
                .shadow(color: BuddyColors.ink.opacity(0.45), radius: 0, x: 6, y: 6)
        }
        .overlay(
            PixelSpeechBubbleShape()
                .stroke(BuddyColors.ink, lineWidth: 5)
                .allowsHitTesting(false)
        )
        .overlay(alignment: .topTrailing) {
            PixelSparkles()
                .foregroundStyle(BuddyColors.cyanDeep)
                .padding(.top, 8)
                .padding(.trailing, 10)
                .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .light)
        .onAppear {
            if model.focus.isRunning {
                showingFocus = true
            } else {
                DispatchQueue.main.async { taskTitleFocused = true }
            }
        }
        .onDisappear { model.focus.interfaceDidHide() }
    }

    private var quickTaskEntry: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("NEW QUEST")
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(BuddyColors.burgundy)
            HStack(spacing: 7) {
                TextField("TYPE A TASK...", text: $taskTitle)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .foregroundStyle(BuddyColors.ink)
                    .background(.white.opacity(0.8))
                    .overlay(
                        Rectangle()
                            .stroke(BuddyColors.ink.opacity(0.8), lineWidth: 2)
                            .allowsHitTesting(false)
                    )
                    .focused($taskTitleFocused)
                    .onSubmit(addTask)
                    .onChange(of: taskTitle) { _, _ in taskAdded = false }
                Button(action: addTask) {
                    Text(model.isAddingTask ? "..." : "ADD")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .frame(width: 48, height: 34)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white)
                .background(BuddyColors.cyanDeep)
                .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAddingTask || !model.taskSourceAvailable)
                .opacity(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !model.taskSourceAvailable ? 0.55 : 1)
            }
            HStack(spacing: 8) {
                Toggle("DUE DATE", isOn: $taskHasDueDate)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                if taskHasDueDate {
                    DatePicker("", selection: $taskDueDate, displayedComponents: .date)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                    DatePicker("", selection: $taskDueTime, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                        .datePickerStyle(.compact)
                        .controlSize(.small)
                }
                Spacer()
            }
            HStack(spacing: 8) {
                Text("CATEGORY")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                Picker("Category", selection: $taskCategory) {
                    ForEach(buddyTaskCategories, id: \.self, content: Text.init)
                }
                .labelsHidden()
                .controlSize(.small)
                if taskAdded {
                    Text("SAVED")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(.green)
                }
            }
            if !model.taskSourceAvailable {
                Text("CONNECT PHONE SYNC OR REMINDERS TO ADD TASKS")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.orange)
            } else if let error = model.quickTaskError {
                Text(error.uppercased())
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(BuddyColors.bubbleSurface)
        .overlay(
            Rectangle()
                .stroke(BuddyColors.burgundy, lineWidth: 2)
                .allowsHitTesting(false)
        )
    }

    @ViewBuilder private var taskSection: some View {
        SectionHeader(title: "Tasks", icon: "checkmark.circle")
        if model.tasks.isEmpty {
            EmptyRow("No open tasks. Nice work!")
        } else {
            ForEach(model.tasks.prefix(8)) { task in
                HStack(spacing: 9) {
                    Button { model.complete(task) } label: { Image(systemName: "circle") }
                        .buttonStyle(.plain).foregroundStyle(BuddyColors.cyanDeep).help("Complete task")
                        .accessibilityLabel("Complete \(task.title)")
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).lineLimit(2)
                        Text(taskMeta(task)).font(.system(size: 9, design: .monospaced)).foregroundStyle(task.isOverdue() ? .red : BuddyColors.bubbleMuted)
                    }
                    Spacer(minLength: 4)
                    Button {
                        model.focus.select(task)
                        showingFocus = true
                    } label: {
                        Image(systemName: "lock.fill")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(BuddyColors.burgundy)
                    .help("Start a Lock In session for \(task.title)")
                    .accessibilityLabel("Lock in on \(task.title)")
                    if task.webURL != nil {
                        Button { model.open(task.webURL) } label: { Image(systemName: "arrow.up.right.square") }
                            .buttonStyle(.borderless).accessibilityLabel("Open reminder link")
                    }
                }
            }
        }
    }

    @ViewBuilder private var eventSection: some View {
        SectionHeader(title: "Today", icon: "calendar")
        let today = model.events.filter { Calendar.current.isDateInToday($0.start) }
        if today.isEmpty {
            EmptyRow("No events left today.")
        } else {
            ForEach(today.prefix(6)) { event in
                eventRow(event)
            }
        }
    }

    @ViewBuilder private var mailSection: some View {
        Button { mailExpanded.toggle() } label: {
            HStack {
                SectionHeader(title: "Inbox", icon: "tray")
                Spacer()
                Text("\(model.mail.count)")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(BuddyColors.bubbleMuted)
                Image(systemName: mailExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(BuddyColors.burgundy)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(mailExpanded ? "Collapse Inbox" : "Expand Inbox")
        .accessibilityLabel(mailExpanded ? "Collapse Inbox" : "Expand Inbox, \(model.mail.count) emails")

        if mailExpanded {
            if model.mail.isEmpty {
                EmptyRow("No recent inbox emails.")
            } else {
                ForEach(model.mail.prefix(6)) { mail in
                    HStack(spacing: 9) {
                        mailRow(mail)
                        Button { model.dismiss(mail) } label: { Image(systemName: "xmark") }
                            .buttonStyle(.plain).foregroundStyle(BuddyColors.cyanDeep).help("Dismiss reminder")
                            .accessibilityLabel("Dismiss \(mail.subject)")
                    }
                }
            }
        }
    }

    @ViewBuilder private func eventRow(_ event: CalendarItem) -> some View {
        let row = HStack {
            Text(event.isAllDay ? "All day" : event.start.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 9, weight: .bold, design: .monospaced).monospacedDigit()).foregroundStyle(BuddyColors.cyanDeep).frame(width: 58, alignment: .leading)
            Text(event.title).foregroundStyle(.primary).lineLimit(2)
            Spacer()
        }
        if let url = event.webURL {
            Button { model.open(url) } label: { row }.buttonStyle(.plain)
        } else {
            row
        }
    }

    @ViewBuilder private func mailRow(_ mail: MailReminder) -> some View {
        let row = VStack(alignment: .leading, spacing: 2) {
            Text(mail.subject).foregroundStyle(.primary).lineLimit(1)
            Text(mail.sender).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        if let url = mail.webURL {
            Button { model.open(url) } label: {
                HStack(spacing: 8) {
                    row
                    Spacer(minLength: 4)
                    Image(systemName: "arrow.up.right.square")
                        .foregroundStyle(BuddyColors.cyanDeep)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open in Gmail")
            .accessibilityLabel("Open email: \(mail.subject)")
        } else {
            row.frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: .now)
        return hour < 12 ? "Good morning!" : hour < 18 ? "Good afternoon!" : "Good evening!"
    }

    private var syncStatus: String {
        if let date = model.lastSyncedAt { return "SYNC // UPDATED \(date.formatted(.relative(presentation: .named)))" }
        return "SYNC // NOT YET UPDATED"
    }

    private func addTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, model.taskSourceAvailable else { return }
        Task {
            if await model.addTask(
                title: title,
                dueDate: taskHasDueDate ? taskDueDate : nil,
                dueTime: taskHasDueDate ? reminderTime(from: taskDueTime) : nil,
                category: taskCategory
            ) {
                taskTitle = ""
                taskHasDueDate = false
                taskAdded = true
                taskTitleFocused = true
            }
        }
    }

    private func taskTiming(_ task: TaskItem) -> String {
        let time = task.dueTime == nil ? "" : " at \(task.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")"
        if task.isOverdue() { return "Overdue\(time)" }
        if task.isDueToday() { return "Due today\(time)" }
        if let due = task.dueDate { return "Due \(due.formatted(date: .abbreviated, time: .omitted))\(time)" }
        return "No due date"
    }

    private func taskMeta(_ task: TaskItem) -> String {
        [taskTiming(task), task.category].compactMap { $0 }.joined(separator: " • ")
    }

    private func reminderTime(from date: Date) -> ReminderTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
    }
}

private struct LockInFocusView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var focus: FocusSessionController

    init(model: AppModel) {
        self.model = model
        focus = model.focus
    }

    private var selectedTask: TaskItem? {
        model.tasks.first { $0.id == focus.selectedTaskID }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("LOCK IN LAB")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .foregroundStyle(BuddyColors.burgundy)
                    if model.tasks.isEmpty {
                        Text("ADD A TASK BEFORE LOCKING IN")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(.orange)
                    } else {
                        Picker("TASK", selection: $focus.selectedTaskID) {
                            ForEach(model.tasks) { task in
                                Text(task.title).tag(task.id)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                        .disabled(focus.isRunning)
                        .accessibilityLabel("Focus task")
                    }
                }

                cameraTile
            }

            VStack(alignment: .leading, spacing: 5) {
                Text("STUDY MODE")
                    .font(.system(size: 9, weight: .black, design: .monospaced))
                    .foregroundStyle(BuddyColors.burgundy)
                Picker("Study mode", selection: $focus.studyMode) {
                    ForEach(FocusStudyMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .disabled(focus.isRunning)
                .accessibilityLabel("Study mode")
                Text(focus.studyMode.detail)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(BuddyColors.bubbleMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 7) {
                Text(sessionStatusTitle)
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(sessionStatusColor)
                Text(FocusTime.formatted(seconds: focus.remainingSeconds))
                    .font(.system(size: 34, weight: .black, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(BuddyColors.ink)
                    .accessibilityLabel("\(focus.remainingSeconds / 60) minutes, \(focus.remainingSeconds % 60) seconds remaining")
                ProgressView(value: focus.progress)
                    .tint(BuddyColors.cyanDeep)
                HStack(spacing: 8) {
                    Text(focus.attentionState.detail ?? (focus.isRunning ? "FACE SCAN ACTIVE" : "LOCAL FACE SCAN READY"))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text("ALERTS \(focus.alertCount)")
                }
                .font(.system(size: 8, weight: .black, design: .monospaced))
                .foregroundStyle(sessionStatusColor)
            }
            .frame(maxWidth: .infinity)
            .padding(10)
            .background(BuddyColors.bubbleSurface)
            .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))

            HStack(spacing: 6) {
                ForEach([25, 45, 60], id: \.self) { minutes in
                    Button("\(minutes)M") { focus.setDuration(minutes) }
                        .buttonStyle(.plain)
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .foregroundStyle(focus.durationMinutes == minutes ? .white : BuddyColors.ink)
                        .frame(maxWidth: .infinity, minHeight: 28)
                        .background(focus.durationMinutes == minutes ? BuddyColors.burgundy : BuddyColors.bubbleSurface)
                        .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
                        .disabled(focus.isRunning)
                }
            }

            HStack(spacing: 7) {
                if !focus.isRunning {
                    Button(focus.completed ? "START AGAIN" : "START") {
                        focus.start()
                    }
                    .disabled(selectedTask == nil)
                } else {
                    Button(focus.isPaused ? "RESUME" : "PAUSE") {
                        focus.isPaused ? focus.resume() : focus.pause()
                    }
                    Button("RECAL") { focus.recalibrate() }
                    Button("END") { focus.end() }
                }
            }
            .buttonStyle(PixelFocusButtonStyle())
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 5) {
                Label("Camera frames stay on this Mac.", systemImage: "hand.raised.fill")
                    .foregroundStyle(BuddyColors.burgundy)
                Text("The preview is never recorded or uploaded. Closing this popup keeps an active session running.")
                    .foregroundStyle(BuddyColors.bubbleMuted)
                Text("Face and gaze checks are estimates, not a medical or accessibility diagnostic.")
                    .foregroundStyle(BuddyColors.bubbleMuted)
            }
            .font(.system(size: 8, weight: .bold, design: .monospaced))

            Spacer(minLength: 0)
        }
        .onAppear {
            if focus.selectedTaskID.isEmpty { focus.select(model.tasks.first) }
            focus.prepareCamera()
        }
        .onDisappear { focus.interfaceDidHide() }
        .onChange(of: focus.completed) { _, completed in
            if completed { model.character.play(.happy, for: .seconds(2)) }
        }
    }

    private var cameraTile: some View {
        ZStack(alignment: .bottomLeading) {
            Rectangle().fill(BuddyColors.ink)
            FocusCameraPreview(session: focus.cameraSession)
            if focus.cameraState != .ready {
                VStack(spacing: 4) {
                    Image(systemName: focus.cameraState == .denied ? "video.slash.fill" : "video.fill")
                    Text(focus.cameraStatus)
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                }
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(5)
                .background(BuddyColors.ink.opacity(0.8))
            }
            Text("YOU")
                .font(.system(size: 7, weight: .black, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 2)
                .background(BuddyColors.burgundy)
        }
        .frame(width: 108, height: 82)
        .clipped()
        .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(focus.cameraStatus)
    }

    private var sessionStatusTitle: String {
        if focus.completed { return "QUEST COMPLETE" }
        if focus.isPaused { return "PAUSED" }
        if focus.isRunning { return focus.attentionState.title }
        return "READY?"
    }

    private var sessionStatusColor: Color {
        if focus.completed { return .green }
        switch focus.attentionState {
        case .alerted: return .red
        case .distracted: return .orange
        case .focused: return .green
        case .waiting, .calibrating: return BuddyColors.burgundy
        }
    }
}

private struct PixelFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: 30)
            .background(configuration.isPressed ? BuddyColors.cyanDeep : BuddyColors.burgundy)
            .overlay(Rectangle().stroke(BuddyColors.ink, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.82 : 1)
    }
}

private struct SectionHeader: View {
    let title: String
    let icon: String
    var body: some View {
        Label(title, systemImage: icon)
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .foregroundStyle(BuddyColors.burgundy)
    }
}

private struct EmptyRow: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View { Text(text).font(.system(size: 10, design: .monospaced)).foregroundStyle(BuddyColors.bubbleMuted).padding(.leading, 4) }
}

private struct PixelSpeechBubbleShape: Shape {
    func path(in rect: CGRect) -> Path {
        let x = rect.minX
        let y = rect.minY
        let w = rect.width
        let h = rect.height
        var path = Path()
        path.move(to: CGPoint(x: x + 22, y: y + 3))
        path.addLine(to: CGPoint(x: x + w - 30, y: y + 3))
        path.addLine(to: CGPoint(x: x + w - 30, y: y + 9))
        path.addLine(to: CGPoint(x: x + w - 16, y: y + 9))
        path.addLine(to: CGPoint(x: x + w - 16, y: y + 16))
        path.addLine(to: CGPoint(x: x + w - 8, y: y + 16))
        path.addLine(to: CGPoint(x: x + w - 8, y: y + h - 58))
        path.addLine(to: CGPoint(x: x + w - 16, y: y + h - 58))
        path.addLine(to: CGPoint(x: x + w - 16, y: y + h - 48))
        path.addLine(to: CGPoint(x: x + w - 54, y: y + h - 48))
        path.addLine(to: CGPoint(x: x + w - 42, y: y + h - 8))
        path.addLine(to: CGPoint(x: x + w - 84, y: y + h - 48))
        path.addLine(to: CGPoint(x: x + 22, y: y + h - 48))
        path.addLine(to: CGPoint(x: x + 22, y: y + h - 54))
        path.addLine(to: CGPoint(x: x + 9, y: y + h - 54))
        path.addLine(to: CGPoint(x: x + 9, y: y + h - 66))
        path.addLine(to: CGPoint(x: x + 3, y: y + h - 66))
        path.addLine(to: CGPoint(x: x + 3, y: y + 22))
        path.addLine(to: CGPoint(x: x + 9, y: y + 22))
        path.addLine(to: CGPoint(x: x + 9, y: y + 9))
        path.addLine(to: CGPoint(x: x + 22, y: y + 9))
        path.closeSubpath()
        return path
    }
}

private struct PixelSparkles: View {
    var body: some View {
        VStack(spacing: 2) {
            Rectangle().frame(width: 4, height: 4)
            HStack(spacing: 2) {
                Rectangle().frame(width: 4, height: 4)
                Rectangle().frame(width: 4, height: 4)
            }
            Rectangle().frame(width: 4, height: 4)
        }
        .frame(width: 12, height: 12)
        .accessibilityHidden(true)
    }
}

private struct StatusBanner: View {
    let icon: String
    let text: String
    let color: Color
    var body: some View {
        Label(text, systemImage: icon)
            .font(.caption)
            .foregroundStyle(.primary)
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(color.opacity(0.13), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct OnboardingView: View {
    @ObservedObject var model: AppModel
    let finish: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                CharacterSpriteView(state: hasConnectedSource ? .wave : .idle).frame(width: 112, height: 112)
                VStack(spacing: 6) {
                    Text("Meet Task Buddy").font(.system(size: 28, weight: .bold, design: .rounded))
                    Text("Local reminders, today’s calendar, and your newest Apple Mail Inbox messages.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                }

                GroupBox("Apple access") {
                    VStack(spacing: 12) {
                        PermissionRow(
                            title: "Reminders",
                            detail: "Show and complete your open reminders.",
                            icon: "checkmark.circle",
                            state: model.remindersState,
                            request: model.requestRemindersAccess
                        )
                        Divider()
                        PermissionRow(
                            title: "Calendar",
                            detail: "Show today’s events and ten-minute alerts.",
                            icon: "calendar",
                            state: model.calendarState,
                            request: model.requestCalendarAccess
                        )
                    }
                    .padding(.top, 5)
                }

                GroupBox("Apple Mail Inbox") {
                    AppleMailSetupFields(model: model)
                        .padding(.top, 5)
                }

                GroupBox("Reminder times") {
                    ReminderTimeEditor(preferences: $model.preferences).padding(.top, 5)
                }

                Toggle("Launch Task Buddy when I log in", isOn: $model.preferences.launchAtLogin)
                if let error = model.errorMessage {
                    StatusBanner(icon: "exclamationmark.triangle.fill", text: error, color: .red)
                }

                Button("Start using Task Buddy") {
                    Task {
                        await model.requestNotifications()
                        model.applyLaunchAtLogin()
                        model.finishOnboarding()
                        finish()
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                Text("You can finish now and connect any skipped source later in the Control Center.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(30)
        }
        .frame(width: 520)
    }

    private var hasConnectedSource: Bool {
        model.remindersState == .connected || model.calendarState == .connected || model.mailState == .connected
            || model.supabaseState == .connected
    }
}

struct BuddyControlCenterView: View {
    @ObservedObject var model: AppModel
    @State private var confirmsQuit = false
    @State private var taskTitle = ""
    @State private var taskHasDueDate = false
    @State private var taskDueDate = Date()
    @State private var taskDueTime = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: .now) ?? .now
    @State private var taskCategory = buddyTaskCategories[0]
    @State private var taskAdded = false
    @FocusState private var taskTitleFocused: Bool

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    CharacterSpriteView(state: .idle)
                        .frame(width: 72, height: 72)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Your buddy is running")
                            .font(.system(.title2, design: .rounded, weight: .bold))
                        Label("Visible above windows on every desktop", systemImage: "pin.fill")
                            .foregroundStyle(.secondary)
                        Text("Closing this Control Center leaves the buddy running.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Buddy appearance") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Buddy size")
                        Spacer()
                        Text(model.preferences.petScale, format: .percent.precision(.fractionLength(0)))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    Slider(
                        value: $model.preferences.petScale,
                        in: AppPreferences.petScaleRange,
                        step: 0.05
                    )
                    .accessibilityLabel("Buddy size")
                    .accessibilityValue(model.preferences.petScale.formatted(.percent.precision(.fractionLength(0))))
                    .onChange(of: model.preferences.petScale) { _, _ in model.savePreferences() }
                    Text("Drag the buddy itself to move it anywhere on screen.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Quick Launcher") {
                LabeledContent("Search the web") {
                    Text("⌥ ⇧ Return").font(.system(.body, design: .monospaced, weight: .semibold))
                }
                LabeledContent("Open an app or website") {
                    Text("⌥ ⇧ Space").font(.system(.body, design: .monospaced, weight: .semibold))
                }
                Text("These shortcuts work globally while Task Buddy is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = model.launcherShortcutError {
                    Label(error, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            Section("Buddy Tasks") {
                Text(model.supabaseState == .connected
                     ? "Buddy Tasks sync with your phone through Supabase."
                     : "Buddy Tasks are stored in Apple Reminders until phone sync is connected.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                LabeledContent("Task") {
                    TextField("What needs doing?", text: $taskTitle)
                        .focused($taskTitleFocused)
                        .onSubmit(addTask)
                        .onChange(of: taskTitle) { _, _ in taskAdded = false }
                }
                Toggle("Add a due date", isOn: $taskHasDueDate)
                if taskHasDueDate {
                    DatePicker("Due date", selection: $taskDueDate, displayedComponents: .date)
                    DatePicker("Due time", selection: $taskDueTime, displayedComponents: .hourAndMinute)
                }
                Picker("Category", selection: $taskCategory) {
                    ForEach(buddyTaskCategories, id: \.self, content: Text.init)
                }
                HStack {
                    Button("Add Task", action: addTask)
                        .buttonStyle(.borderedProminent)
                        .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isAddingTask || !model.taskSourceAvailable)
                    if model.isAddingTask { ProgressView().controlSize(.small) }
                    if taskAdded {
                        Label("Added", systemImage: "checkmark.circle.fill")
                            .font(.caption).foregroundStyle(.green)
                    }
                }
                if !model.taskSourceAvailable {
                    Text("Connect phone sync below or allow Reminders access to create Buddy Tasks.")
                        .font(.caption).foregroundStyle(.secondary)
                } else if let error = model.quickTaskError {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .font(.caption).foregroundStyle(.red)
                }

                if !model.tasks.isEmpty {
                    Divider()
                    ForEach(model.tasks.prefix(6)) { task in
                        HStack(spacing: 9) {
                            Button { model.complete(task) } label: { Image(systemName: "circle") }
                                .buttonStyle(.borderless)
                                .accessibilityLabel("Complete \(task.title)")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(task.title).lineLimit(1)
                                Text(taskMeta(task)).font(.caption).foregroundStyle(task.isOverdue() ? .red : .secondary)
                            }
                        }
                    }
                }
            }
            Section("Phone sync — Supabase") {
                SupabaseSetupFields(model: model)
                if model.hasSupabaseSession {
                    Button("Disconnect phone sync", role: .destructive, action: model.disconnectSupabase)
                }
            }
            Section("Apple access") {
                PermissionRow(
                    title: "Reminders",
                    detail: "All available lists",
                    icon: "checkmark.circle",
                    state: model.remindersState,
                    request: model.requestRemindersAccess
                )
                PermissionRow(
                    title: "Calendar",
                    detail: "All available calendars",
                    icon: "calendar",
                    state: model.calendarState,
                    request: model.requestCalendarAccess
                )
            }
            Section("Apple Mail Inbox") {
                AppleMailSetupFields(model: model)
                if model.isAppleMailConnected {
                    Button("Disconnect Apple Mail", role: .destructive, action: model.disconnectAppleMail)
                }
            }
            Section("Reminders") { ReminderTimeEditor(preferences: $model.preferences) }
            Section("App") {
                Toggle("Launch at login", isOn: $model.preferences.launchAtLogin)
                    .onChange(of: model.preferences.launchAtLogin) { _, _ in model.applyLaunchAtLogin() }
                Button("Quit Task Buddy…", role: .destructive) { confirmsQuit = true }
            }
            if let error = model.errorMessage { StatusBanner(icon: "exclamationmark.triangle.fill", text: error, color: .red) }
        }
        .formStyle(.grouped)
        .padding()
        .frame(width: 540, height: 700)
        .onDisappear { model.savePreferences() }
        .alert("Quit Task Buddy?", isPresented: $confirmsQuit) {
            Button("Cancel", role: .cancel) {}
            Button("Quit", role: .destructive) { NSApp.terminate(nil) }
        } message: {
            Text("This closes both the Control Center and the floating buddy.")
        }
    }

    private func addTask() {
        let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, model.taskSourceAvailable else { return }
        Task {
            if await model.addTask(
                title: title,
                dueDate: taskHasDueDate ? taskDueDate : nil,
                dueTime: taskHasDueDate ? reminderTime(from: taskDueTime) : nil,
                category: taskCategory
            ) {
                taskTitle = ""
                taskHasDueDate = false
                taskAdded = true
                taskTitleFocused = true
            }
        }
    }

    private func taskTiming(_ task: TaskItem) -> String {
        let time = task.dueTime == nil ? "" : " at \(task.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")"
        if task.isOverdue() { return "Overdue\(time)" }
        if task.isDueToday() { return "Due today\(time)" }
        if let due = task.dueDate { return "Due \(due.formatted(date: .abbreviated, time: .omitted))\(time)" }
        return "No due date"
    }

    private func taskMeta(_ task: TaskItem) -> String {
        [taskTiming(task), task.category].compactMap { $0 }.joined(separator: " • ")
    }

    private func reminderTime(from date: Date) -> ReminderTime {
        let components = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: components.hour ?? 9, minute: components.minute ?? 0)
    }
}

private struct SupabaseSetupFields: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !model.isSupabaseConfigured {
                Label("This build is missing SupabaseConfig.json.", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption).foregroundStyle(.orange)
            }
            TextField("Email", text: $model.preferences.supabaseEmail)
                .textContentType(.username)
                .accessibilityLabel("Phone sync email")
            SecureField("Password", text: $model.supabasePassword)
                .textContentType(.password)
                .accessibilityLabel("Phone sync password")

            if model.isSupabasePasswordRecovery {
                SecureField("New password", text: $model.newSupabasePassword)
                    .textContentType(.newPassword)
                    .accessibilityLabel("New phone sync password")
                SecureField("Confirm new password", text: $model.confirmSupabasePassword)
                    .textContentType(.newPassword)
                    .accessibilityLabel("Confirm new phone sync password")
            }

            if let error = model.supabaseFieldError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
            } else if model.supabaseState == .connected {
                Label("Connected. New Buddy Tasks will sync with your phone.", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else if let message = model.supabaseResetMessage {
                Label(message, systemImage: "envelope.fill")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text("Use the same email and password as the Task Buddy phone app.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button(
                    model.isSupabasePasswordRecovery
                        ? "Save new password"
                        : model.hasSupabaseSession ? "Test Connection" : "Connect phone sync",
                    action: model.isSupabasePasswordRecovery ? model.completeSupabasePasswordReset : model.connectSupabase
                )
                    .buttonStyle(.borderedProminent)
                    .disabled(model.supabaseState == .requesting || model.isSupabaseResettingPassword || !model.isSupabaseConfigured)
                if model.supabaseState == .requesting || model.isSupabaseResettingPassword { ProgressView().controlSize(.small) }
                if !model.isSupabasePasswordRecovery {
                    Button("Forgot password?", action: model.requestSupabasePasswordReset)
                        .buttonStyle(.link)
                        .disabled(model.isSupabaseResettingPassword || !model.isSupabaseConfigured)
                }
            }
            Text("The password is never saved. A restricted session token is stored in Application Support with owner-only file permissions.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let icon: String
    let state: SourceConnectionState
    let request: () -> Void

    var body: some View {
        HStack(spacing: 11) {
            Image(systemName: icon).frame(width: 20).foregroundStyle(BuddyColors.cyanDeep)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
                if case .failed(let message) = state {
                    Text(message).font(.caption).foregroundStyle(.red)
                }
            }
            Spacer()
            if state == .requesting {
                ProgressView().controlSize(.small).accessibilityLabel("Requesting \(title) access")
            } else if state == .connected {
                Label("Allowed", systemImage: "checkmark.circle.fill").foregroundStyle(.green).font(.caption)
            } else {
                Button(state == .denied ? "Open Settings" : "Allow") {
                    if state == .denied {
                        openPrivacySettings(for: title)
                    } else {
                        request()
                    }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func openPrivacySettings(for title: String) {
        let anchor = title == "Calendar" ? "Privacy_Calendars" : "Privacy_Reminders"
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

private struct AppleMailSetupFields: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            if let error = model.mailFieldError {
                Label(error, systemImage: "exclamationmark.circle.fill")
                    .font(.caption).foregroundStyle(.red)
                    .accessibilityLabel("Apple Mail setup error: \(error)")
            } else if model.mailState == .connected {
                Label("Connected to the Inbox in Apple Mail.", systemImage: "checkmark.circle.fill")
                    .font(.caption).foregroundStyle(.green)
            } else {
                Text("Uses the accounts already signed in to Apple Mail. No Gmail password is needed.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            HStack {
                Button(model.isAppleMailConnected ? "Refresh Apple Mail" : "Connect Apple Mail", action: model.connectAppleMail)
                    .buttonStyle(.borderedProminent)
                    .disabled(model.mailState == .requesting)
                if model.mailState == .requesting { ProgressView().controlSize(.small) }
            }
            Text("macOS will ask whether Task Buddy may control Mail. Allow it to show the newest 20 Inbox message headers.")
                .font(.caption).foregroundStyle(.secondary)
            Text("Task Buddy does not read message bodies or change your mail.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ReminderTimeEditor: View {
    @Binding var preferences: AppPreferences

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
            GridRow {
                Text("Daily digest")
                DatePicker("", selection: timeBinding(for: \AppPreferences.digestTime), displayedComponents: .hourAndMinute).labelsHidden()
            }
            optionalTimeRow("First nudge", keyPath: \AppPreferences.firstNudgeTime, fallback: ReminderTime(hour: 14, minute: 0))
            optionalTimeRow("Second nudge", keyPath: \AppPreferences.secondNudgeTime, fallback: ReminderTime(hour: 18, minute: 0))
        }
    }

    @ViewBuilder private func optionalTimeRow(_ title: String, keyPath: WritableKeyPath<AppPreferences, ReminderTime?>, fallback: ReminderTime) -> some View {
        GridRow {
            Toggle(title, isOn: Binding(
                get: { preferences[keyPath: keyPath] != nil },
                set: { preferences[keyPath: keyPath] = $0 ? fallback : nil }
            ))
            DatePicker("", selection: optionalTimeBinding(for: keyPath, fallback: fallback), displayedComponents: .hourAndMinute)
                .labelsHidden().disabled(preferences[keyPath: keyPath] == nil)
        }
    }

    private func timeBinding(for keyPath: WritableKeyPath<AppPreferences, ReminderTime>) -> Binding<Date> {
        Binding(
            get: { date(from: preferences[keyPath: keyPath]) },
            set: { preferences[keyPath: keyPath] = reminderTime(from: $0) }
        )
    }

    private func optionalTimeBinding(for keyPath: WritableKeyPath<AppPreferences, ReminderTime?>, fallback: ReminderTime) -> Binding<Date> {
        Binding(
            get: { date(from: preferences[keyPath: keyPath] ?? fallback) },
            set: { preferences[keyPath: keyPath] = reminderTime(from: $0) }
        )
    }

    private func date(from time: ReminderTime) -> Date {
        Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: time.hour, minute: time.minute)) ?? .now
    }

    private func reminderTime(from date: Date) -> ReminderTime {
        let values = Calendar.current.dateComponents([.hour, .minute], from: date)
        return ReminderTime(hour: values.hour ?? 9, minute: values.minute ?? 0)
    }
}
