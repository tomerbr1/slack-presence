import SwiftUI

@main
struct SlackPresenceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Menu bar only - no main window
        Settings {
            EmptyView()
        }
    }
}
