import Foundation
import SwiftUI

@Observable
final class AppState {
    // Current state
    var currentPresence: SlackPresence = .unknown
    var isInCall: Bool = false
    var hasValidCredentials: Bool = false
    var isDNDActive: Bool = false

    // Call detection status for display
    var isInMeeting: Bool = false
    var currentMeetingTitle: String? = nil
    var isOutOfOffice: Bool = false
    var oooEndDate: Date? = nil
    var micActive: Bool = false
    var manualInCallOverride: Bool? = nil  // nil = auto-detect, true/false = manual

    // Status display
    var statusText: String = "Initializing..."
    var lastError: String?
    var lastUpdate: Date?

    // Override mode
    var manualOverride: SlackPresence? = nil

    // Computed
    var effectivePresence: SlackPresence {
        if let override = manualOverride {
            return override
        }
        return currentPresence
    }

    var menuBarIcon: String {
        if isOutOfOffice { return "airplane" }
        if isInMeeting { return "calendar" }
        if isInCall { return "headphones" }
        switch effectivePresence {
        case .active:
            return "sun.max.fill"
        case .away:
            // moon.zzz.fill is a built-in SF Symbol for away + DND
            return isDNDActive ? "moon.zzz.fill" : "moon.fill"
        case .unknown:
            return "questionmark.circle"
        }
    }

    /// Whether the icon needs a DND badge overlay (only for Active + DND)
    var needsDNDBadge: Bool {
        return isDNDActive && effectivePresence == .active && !isInCall && !isInMeeting && !isOutOfOffice
    }

    var menuBarIconColor: Color {
        if isOutOfOffice { return .orange }
        if isInMeeting { return .blue }
        if isInCall { return .purple }
        switch effectivePresence {
        case .active:
            return .green
        case .away:
            return .gray
        case .unknown:
            return .orange
        }
    }

    func updateStatus(_ text: String) {
        statusText = text
        lastUpdate = Date()
        lastError = nil
    }

    func setError(_ error: String) {
        lastError = error
        statusText = "Error: \(error)"
    }

    func clearOverride() {
        manualOverride = nil
    }
}

// Configuration state
@Observable
final class ConfigState {
    var schedule: WeekSchedule = WeekSchedule()
    var callDetectionEnabled: Bool = true
    var pauseNotificationsWhenAway: Bool = true
    var scheduledStatuses: [ScheduledStatus] = []
    var callStartDelay: Int = 10  // Seconds to confirm call started
    var callEndDelay: Int = 3     // Seconds to confirm call ended
    var disabledDeviceUIDs: Set<String> = []  // Device UIDs user has disabled
    var hasCompletedOnboarding: Bool = false
    var calendarSyncEnabled: Bool = false
    var selectedCalendarIDs: Set<String> = []
    var meetingEmoji: String = ":headphones:"
    var meetingStatusText: String = "In a meeting"
    var calendarSyncIntervalMinutes: Int = 15
    var triggerOnBusy: Bool = true
    var triggerOnTentative: Bool = true
    var triggerOnFree: Bool = false
    var oooEnabled: Bool = false
    var oooEmoji: String = ":no_entry:"
    var oooStatusText: String = "Out of office"
    var oooPauseNotifications: Bool = true

    // Track current active scheduled status
    var activeScheduledStatus: ScheduledStatus? = nil

    func load(from config: AppConfig) {
        schedule = config.schedules
        callDetectionEnabled = config.callDetectionEnabled
        pauseNotificationsWhenAway = config.pauseNotificationsWhenAway
        scheduledStatuses = config.scheduledStatuses
        callStartDelay = config.callStartDelay
        callEndDelay = config.callEndDelay
        disabledDeviceUIDs = config.disabledDeviceUIDs
        hasCompletedOnboarding = config.hasCompletedOnboarding
        calendarSyncEnabled = config.calendarSyncEnabled
        selectedCalendarIDs = config.selectedCalendarIDs
        meetingEmoji = config.meetingEmoji
        meetingStatusText = config.meetingStatusText
        calendarSyncIntervalMinutes = config.calendarSyncIntervalMinutes
        triggerOnBusy = config.triggerOnBusy
        triggerOnTentative = config.triggerOnTentative
        triggerOnFree = config.triggerOnFree
        oooEnabled = config.oooEnabled
        oooEmoji = config.oooEmoji
        oooStatusText = config.oooStatusText
        oooPauseNotifications = config.oooPauseNotifications

        // Apply to MicMonitor
        MicMonitor.shared.callStartDelay = TimeInterval(callStartDelay)
        MicMonitor.shared.callEndDelay = TimeInterval(callEndDelay)
        MicMonitor.shared.userDisabledDeviceUIDs = disabledDeviceUIDs
    }

    func toConfig() -> AppConfig {
        var config = AppConfig()
        config.schedules = schedule
        config.callDetectionEnabled = callDetectionEnabled
        config.pauseNotificationsWhenAway = pauseNotificationsWhenAway
        config.scheduledStatuses = scheduledStatuses
        config.callStartDelay = callStartDelay
        config.callEndDelay = callEndDelay
        config.disabledDeviceUIDs = disabledDeviceUIDs
        config.hasCompletedOnboarding = hasCompletedOnboarding
        config.calendarSyncEnabled = calendarSyncEnabled
        config.selectedCalendarIDs = selectedCalendarIDs
        config.meetingEmoji = meetingEmoji
        config.meetingStatusText = meetingStatusText
        config.calendarSyncIntervalMinutes = calendarSyncIntervalMinutes
        config.triggerOnBusy = triggerOnBusy
        config.triggerOnTentative = triggerOnTentative
        config.triggerOnFree = triggerOnFree
        config.oooEnabled = oooEnabled
        config.oooEmoji = oooEmoji
        config.oooStatusText = oooStatusText
        config.oooPauseNotifications = oooPauseNotifications
        return config
    }
}
