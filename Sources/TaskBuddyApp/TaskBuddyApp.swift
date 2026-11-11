import SwiftUI

@main
struct TaskBuddyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            BuddyControlCenterView(model: .shared)
        }
    }
}
