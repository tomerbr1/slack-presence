import Foundation

// App-wide notification names
extension Notification.Name {
    /// Open the token help window
    static let openTokenHelp = Notification.Name("openTokenHelp")

    /// Trigger menu bar icon update
    static let updateMenuBarIcon = Notification.Name("updateMenuBarIcon")

    /// Open the schedule editor window
    static let openScheduleEditor = Notification.Name("openScheduleEditor")

    /// Open the status schedule window
    static let openStatusSchedule = Notification.Name("openStatusSchedule")

    /// Open the welcome/onboarding window
    static let openWelcome = Notification.Name("openWelcome")

    /// Open the troubleshooting window
    static let openTroubleshooting = Notification.Name("openTroubleshooting")
}
