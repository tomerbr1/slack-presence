import Foundation
import os.log

private let logger = Logger(subsystem: "com.slackpresence", category: "ScheduleManager")

final class ScheduleManager {
    static let shared = ScheduleManager()

    private var timer: Timer?
    private var isRunning = false

    // Dependencies
    private let configManager = ConfigManager.shared
    private let slackClient = SlackClient.shared
    private let micMonitor = MicMonitor.shared
    private let calendarMonitor = CalendarMonitor.shared
    private let networkMonitor = NetworkMonitor.shared

    // State
    private var appState: AppState?
    private var configState: ConfigState?

    private let stateLock = NSLock()
    private var lastAppliedPresence: SlackPresence?
    private var lastCallState: Bool = false
    private var lastMeetingState: Bool = false
    private var lastAppliedScheduledStatus: ScheduledStatus?
    private var dndWasSetByUs: Bool = false

    private init() {}

    // MARK: - Lifecycle

    func start(appState: AppState, configState: ConfigState) {
        guard !isRunning else { return }

        self.appState = appState
        self.configState = configState

        isRunning = true

        // Load config
        let config = configManager.loadConfig()
        configState.load(from: config)

        // Check credentials
        appState.hasValidCredentials = slackClient.hasValidCredentials

        // Set up call monitoring callback
        micMonitor.onCallStateChanged = { [weak self] inCall in
            self?.handleCallStateChange(inCall)
        }

        // Start call detection if enabled
        if configState.callDetectionEnabled {
            micMonitor.startMonitoring()
        }

        // Set up calendar monitoring callback
        calendarMonitor.onMeetingStateChanged = { [weak self] inMeeting, endDate in
            self?.handleMeetingStateChange(inMeeting, meetingEndDate: endDate)
        }

        // Start calendar sync if enabled
        if configState.calendarSyncEnabled {
            calendarMonitor.selectedCalendarIDs = configState.selectedCalendarIDs
            calendarMonitor.eventFetchInterval = TimeInterval(configState.calendarSyncIntervalMinutes * 60)
            Task { await calendarMonitor.requestAccess() }
            calendarMonitor.startMonitoring()
        }

        // Setup connectivity restored handler
        networkMonitor.onConnectivityRestored = { [weak self] in
            Task { @MainActor in
                self?.appState?.statusText = "Reconnected - syncing..."
            }
            Task {
                await self?.syncAfterReconnect()
            }
        }
        networkMonitor.start()

        // Check immediately - sync actual presence first for accurate icon
        Task {
            await syncActualPresence()  // Get real status first
            await checkAndApply()       // Then apply schedule if needed
        }

        // Schedule checks every 60 seconds
        timer = Timer.scheduledTimer(withTimeInterval: 60.0, repeats: true) { [weak self] _ in
            Task {
                await self?.checkAndApply()
            }
        }

        appState.updateStatus("Started")
    }

    /// Sync state after network connectivity is restored
    private func syncAfterReconnect() async {
        logger.info("Network connectivity restored - syncing state")

        // Re-sync actual presence from Slack
        await syncActualPresence()

        // Check if schedule requires state change
        await checkAndApply()

        await MainActor.run {
            appState?.updateStatus("Connected")
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        micMonitor.stopMonitoring()
        calendarMonitor.stopMonitoring()
        networkMonitor.stop()
        isRunning = false
    }

    // MARK: - Core Logic

    private func checkAndApply() async {
        guard let appState = appState, let configState = configState else { return }

        // Check DND status
        await checkDNDStatus()

        // Skip if in meeting or call (auto-detection takes priority over schedule)
        if appState.isInMeeting { return }
        if appState.isInCall { return }

        // Determine target presence (nil means schedule disabled - don't manage)
        guard let targetPresence = determineTargetPresence() else {
            // Schedule disabled for today - sync actual presence but don't change it
            await syncActualPresence()
            await MainActor.run {
                appState.updateStatus("Schedule disabled")
            }
            // Check and apply scheduled statuses even if presence not managed
            await checkAndApplyScheduledStatus()
            return
        }

        // Update UI state
        await MainActor.run {
            appState.currentPresence = targetPresence
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        // Handle presence change
        let previousPresence = stateLock.withLock { lastAppliedPresence }
        if targetPresence != previousPresence {
            do {
                try await slackClient.setPresence(targetPresence)
                stateLock.withLock { lastAppliedPresence = targetPresence }

                // Handle DND when going away
                if targetPresence == .away && configState.pauseNotificationsWhenAway {
                    await handleDNDForAway(entering: true)
                } else if targetPresence == .active && stateLock.withLock({ dndWasSetByUs }) {
                    await handleDNDForAway(entering: false)
                }

                await MainActor.run {
                    appState.updateStatus("Set to \(targetPresence.displayName)")
                }
            } catch {
                await MainActor.run {
                    appState.setError(error.localizedDescription)
                }
            }
        }

        // Check and apply scheduled statuses
        await checkAndApplyScheduledStatus()
    }

    /// Query actual Slack presence and update icon to match reality
    private func syncActualPresence() async {
        guard let appState = appState else { return }

        do {
            let actualPresence = try await slackClient.fetchPresence()
            let isDND = try await slackClient.fetchDNDStatus()
            await MainActor.run {
                appState.currentPresence = actualPresence
                appState.isDNDActive = isDND
                NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
            }
        } catch {
            // Silently ignore - not critical, will use schedule-based presence
            logger.debug("Failed to sync actual presence: \(error.localizedDescription)")
        }
    }

    private func checkDNDStatus() async {
        guard let appState = appState else { return }

        do {
            let isDND = try await slackClient.fetchDNDStatus()
            await MainActor.run {
                appState.isDNDActive = isDND
                NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
            }
        } catch {
            // Silently ignore DND check failures - not critical
        }
    }

    private func handleDNDForAway(entering: Bool) async {
        guard configState != nil else { return }

        if entering {
            // Calculate minutes until active again
            let minutesUntilActive = calculateMinutesUntilActive()
            if minutesUntilActive > 0 {
                do {
                    try await slackClient.pauseNotifications(minutes: minutesUntilActive)
                    stateLock.withLock { dndWasSetByUs = true }
                    logger.info("Paused notifications for \(minutesUntilActive) minutes")
                } catch {
                    logger.error("Failed to pause notifications: \(error.localizedDescription)")
                }
            }
        } else {
            // Resume notifications
            do {
                try await slackClient.resumeNotifications()
                stateLock.withLock { dndWasSetByUs = false }
                logger.info("Resumed notifications")
            } catch {
                logger.error("Failed to resume notifications: \(error.localizedDescription)")
            }
        }
    }

    private func calculateMinutesUntilActive() -> Int {
        guard let configState = configState else { return 0 }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        let daySchedule = configState.schedule.schedule(for: weekday)

        guard daySchedule.enabled,
              let start = daySchedule.startTime,
              let startHour = start.hour, let startMinute = start.minute else {
            // If today not enabled, pause for a long time (will be resumed tomorrow)
            return 12 * 60  // 12 hours max
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute

        if currentMinutes < startMinutes {
            // Before start time today
            return startMinutes - currentMinutes
        } else {
            // After end time, next active is tomorrow morning
            // For simplicity, pause until midnight + tomorrow's start
            let minutesToMidnight = (24 * 60) - currentMinutes

            // Check tomorrow's schedule
            let tomorrowWeekday = weekday == 7 ? 1 : weekday + 1
            let tomorrowSchedule = configState.schedule.schedule(for: tomorrowWeekday)

            if tomorrowSchedule.enabled,
               let tomorrowStart = tomorrowSchedule.startTime,
               let tomorrowHour = tomorrowStart.hour, let tomorrowMin = tomorrowStart.minute {
                return minutesToMidnight + (tomorrowHour * 60 + tomorrowMin)
            }

            // Default: 12 hours
            return 12 * 60
        }
    }

    private func checkAndApplyScheduledStatus() async {
        guard let appState = appState, let configState = configState else { return }

        // Find currently active scheduled status
        let activeStatus = configState.scheduledStatuses.first { $0.isActiveNow() }

        // Check if status changed
        let previousStatusId = stateLock.withLock { lastAppliedScheduledStatus?.id }
        if activeStatus?.id != previousStatusId {
            if let status = activeStatus {
                // Apply new scheduled status
                do {
                    let slackStatus = SlackStatusEmoji(
                        emoji: status.emoji,
                        text: status.text,
                        expiration: 0
                    )
                    try await slackClient.setStatus(slackStatus)
                    stateLock.withLock { lastAppliedScheduledStatus = status }

                    await MainActor.run {
                        configState.activeScheduledStatus = status
                        appState.updateStatus("Status: \(status.text)")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to set scheduled status: \(error.localizedDescription)")
                    }
                }
            } else if previousStatusId != nil {
                // Clear status (scheduled status ended)
                do {
                    try await slackClient.clearStatus()
                    stateLock.withLock { lastAppliedScheduledStatus = nil }

                    await MainActor.run {
                        configState.activeScheduledStatus = nil
                        appState.updateStatus("Status cleared")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to clear status: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Returns the target presence, or nil if schedule is disabled for today (don't manage)
    private func determineTargetPresence() -> SlackPresence? {
        guard let appState = appState, let configState = configState else {
            return nil
        }

        // Priority 1: Manual override
        if let override = appState.manualOverride {
            return override
        }

        // Priority 2: Schedule-based (only if today's schedule is enabled)
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let daySchedule = configState.schedule.schedule(for: weekday)

        // If schedule is disabled for today, don't manage presence
        guard daySchedule.enabled else {
            return nil
        }

        // Schedule is enabled - manage based on active hours
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        if daySchedule.isActiveAt(hour: hour, minute: minute) {
            return .active
        } else {
            return .away
        }
    }

    // MARK: - Call Handling

    private func handleCallStateChange(_ inCall: Bool) {
        guard let appState = appState else { return }

        Task { @MainActor in
            appState.isInCall = inCall
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        // Don't override auto-meeting with auto-call
        // Manual call override ("Set In Call") DOES override - handled in setManualInCall
        if appState.isInMeeting && appState.manualInCallOverride != true {
            stateLock.withLock { lastCallState = inCall }
            return
        }

        let wasInCall = stateLock.withLock { lastCallState }
        if inCall && !wasInCall {
            // Started a call - set status
            Task {
                do {
                    try await slackClient.setStatus(.inMeeting)
                    await MainActor.run {
                        appState.updateStatus("In call")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to set call status: \(error.localizedDescription)")
                    }
                }
            }
        } else if !inCall && wasInCall {
            // Ended a call - clear status
            Task {
                do {
                    try await slackClient.clearStatus()
                    await MainActor.run {
                        appState.updateStatus("Call ended")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to clear status: \(error.localizedDescription)")
                    }
                }
            }
        }

        stateLock.withLock { lastCallState = inCall }
    }

    // MARK: - Meeting Handling

    private func handleMeetingStateChange(_ inMeeting: Bool, meetingEndDate: Date?) {
        guard let appState = appState, let configState = configState else { return }

        let meeting = calendarMonitor.getCurrentMeeting()
        Task { @MainActor in
            appState.isInMeeting = inMeeting
            appState.currentMeetingTitle = meeting?.title
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        let wasMeeting = stateLock.withLock { lastMeetingState }

        if inMeeting && !wasMeeting {
            // Meeting started - check manual override priority
            if appState.manualOverride != nil || appState.manualInCallOverride == true {
                stateLock.withLock { lastMeetingState = inMeeting }
                return
            }

            // Set meeting status with expiration
            Task {
                do {
                    let meetingStatus: SlackStatusEmoji
                    if let endDate = meetingEndDate {
                        meetingStatus = .meeting(
                            emoji: configState.meetingEmoji,
                            text: configState.meetingStatusText,
                            endDate: endDate
                        )
                    } else {
                        meetingStatus = SlackStatusEmoji(
                            emoji: configState.meetingEmoji,
                            text: configState.meetingStatusText,
                            expiration: 0
                        )
                    }
                    try await slackClient.setStatus(meetingStatus)
                    await MainActor.run {
                        appState.updateStatus("In meeting")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to set meeting status: \(error.localizedDescription)")
                    }
                }
            }
        } else if !inMeeting && wasMeeting {
            // Meeting ended
            if appState.manualOverride != nil || appState.manualInCallOverride == true {
                stateLock.withLock { lastMeetingState = inMeeting }
                return
            }

            // If still in a call (auto-detected), restore call status
            if appState.isInCall {
                Task {
                    do {
                        try await slackClient.setStatus(.inMeeting)
                        await MainActor.run {
                            appState.updateStatus("Meeting ended, in call")
                        }
                    } catch {
                        await MainActor.run {
                            appState.setError("Failed to restore call status: \(error.localizedDescription)")
                        }
                    }
                }
            } else {
                Task {
                    do {
                        try await slackClient.clearStatus()
                        await MainActor.run {
                            appState.updateStatus("Meeting ended")
                        }
                    } catch {
                        await MainActor.run {
                            appState.setError("Failed to clear meeting status: \(error.localizedDescription)")
                        }
                    }
                }
            }
        }

        stateLock.withLock { lastMeetingState = inMeeting }
    }

    // MARK: - Manual Call Override

    func setManualInCall() {
        guard let appState = appState else { return }

        micMonitor.setManualInCall()

        // Immediately update UI and Slack status (no debouncing)
        Task { @MainActor in
            appState.manualInCallOverride = true
            appState.isInCall = true
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        // Set Slack status immediately
        Task {
            do {
                try await slackClient.setStatus(.inMeeting)
                await MainActor.run {
                    appState.updateStatus("In call (manual)")
                }
            } catch {
                await MainActor.run {
                    appState.setError("Failed to set call status: \(error.localizedDescription)")
                }
            }
        }

        stateLock.withLock { lastCallState = true }
    }

    func clearManualInCall() {
        guard let appState = appState, let configState = configState else { return }

        // Force clear and suppress auto-detection for 30 seconds
        micMonitor.forceClearCall()
        stateLock.withLock { lastCallState = false }

        // Immediately update UI
        Task { @MainActor in
            appState.manualInCallOverride = nil
            appState.isInCall = false
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        // If still in a meeting, restore meeting status instead of clearing
        if appState.isInMeeting {
            let meeting = calendarMonitor.getCurrentMeeting()
            Task {
                do {
                    let meetingStatus: SlackStatusEmoji
                    if let endDate = meeting?.endDate {
                        meetingStatus = .meeting(
                            emoji: configState.meetingEmoji,
                            text: configState.meetingStatusText,
                            endDate: endDate
                        )
                    } else {
                        meetingStatus = SlackStatusEmoji(
                            emoji: configState.meetingEmoji,
                            text: configState.meetingStatusText,
                            expiration: 0
                        )
                    }
                    try await slackClient.setStatus(meetingStatus)
                    await MainActor.run {
                        appState.updateStatus("Call cleared, in meeting")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to restore meeting status: \(error.localizedDescription)")
                    }
                }
            }
        } else {
            // Clear Slack status
            Task {
                do {
                    try await slackClient.clearStatus()
                    await MainActor.run {
                        appState.updateStatus("Call cleared (suppressed 30s)")
                    }
                } catch {
                    await MainActor.run {
                        appState.setError("Failed to clear status: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    // MARK: - Manual Meeting Override

    func setManualInMeeting() {
        guard let appState = appState, let configState = configState else { return }

        Task { @MainActor in
            appState.isInMeeting = true
            appState.currentMeetingTitle = nil
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        Task {
            do {
                let meetingStatus = SlackStatusEmoji(
                    emoji: configState.meetingEmoji,
                    text: configState.meetingStatusText,
                    expiration: 0
                )
                try await slackClient.setStatus(meetingStatus)
                await MainActor.run { appState.updateStatus("In meeting (manual)") }
            } catch {
                await MainActor.run { appState.setError(error.localizedDescription) }
            }
        }

        stateLock.withLock { lastMeetingState = true }
    }

    func clearManualMeeting() {
        guard let appState = appState else { return }

        // Check if a real calendar meeting is still active
        let realMeeting = calendarMonitor.isInMeeting()

        Task { @MainActor in
            appState.isInMeeting = realMeeting
            appState.currentMeetingTitle = nil
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        if realMeeting {
            // Real calendar meeting still active - restore calendar meeting status
            stateLock.withLock { lastMeetingState = true }
        } else {
            // No real meeting - clear status
            stateLock.withLock { lastMeetingState = false }
            Task {
                do {
                    try await slackClient.clearStatus()
                    await MainActor.run { appState.updateStatus("Meeting cleared") }
                } catch {
                    await MainActor.run { appState.setError(error.localizedDescription) }
                }
            }
        }
    }

    // MARK: - Manual Controls

    func forceActive() async {
        guard let appState = appState else { return }

        await MainActor.run {
            appState.manualOverride = .active
            appState.currentPresence = .active
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        do {
            try await slackClient.setPresence(.active)
            stateLock.withLock { lastAppliedPresence = .active }
            await MainActor.run {
                appState.updateStatus("Forced Active")
            }
        } catch {
            await MainActor.run {
                appState.setError(error.localizedDescription)
            }
        }
    }

    func forceAway() async {
        guard let appState = appState else { return }

        await MainActor.run {
            appState.manualOverride = .away
            appState.currentPresence = .away
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        do {
            try await slackClient.setPresence(.away)
            stateLock.withLock { lastAppliedPresence = .away }
            await MainActor.run {
                appState.updateStatus("Forced Away")
            }
        } catch {
            await MainActor.run {
                appState.setError(error.localizedDescription)
            }
        }
    }

    func resumeSchedule() async {
        guard let appState = appState else { return }

        await MainActor.run {
            appState.clearOverride()
            NotificationCenter.default.post(name: .updateMenuBarIcon, object: nil)
        }

        await checkAndApply()
    }

    // MARK: - Config Updates

    func updateCallDetection(enabled: Bool) {
        configState?.callDetectionEnabled = enabled

        if enabled {
            micMonitor.startMonitoring()
        } else {
            micMonitor.stopMonitoring()
        }
    }

    func updateCalendarSync(enabled: Bool) {
        configState?.calendarSyncEnabled = enabled
        if enabled {
            // Re-set callback (stopMonitoring nils it out)
            calendarMonitor.onMeetingStateChanged = { [weak self] inMeeting, endDate in
                self?.handleMeetingStateChange(inMeeting, meetingEndDate: endDate)
            }
            if let configState = configState {
                calendarMonitor.selectedCalendarIDs = configState.selectedCalendarIDs
                calendarMonitor.eventFetchInterval = TimeInterval(configState.calendarSyncIntervalMinutes * 60)
            }
            Task { await calendarMonitor.requestAccess() }
            calendarMonitor.startMonitoring()
        } else {
            calendarMonitor.stopMonitoring()
        }
    }

    func updateCalendarSyncInterval(minutes: Int) {
        calendarMonitor.eventFetchInterval = TimeInterval(minutes * 60)
    }

    func updateSelectedCalendars(_ ids: Set<String>) {
        calendarMonitor.selectedCalendarIDs = ids
    }

    func syncCalendarNow() {
        calendarMonitor.forceSync()
    }

    func saveConfig() {
        guard let configState = configState else { return }

        do {
            try configManager.saveConfig(configState.toConfig())
        } catch {
            appState?.setError("Failed to save config: \(error.localizedDescription)")
        }
    }

    func updatePauseNotifications(enabled: Bool) {
        configState?.pauseNotificationsWhenAway = enabled
    }

    func addScheduledStatus(_ status: ScheduledStatus) {
        configState?.scheduledStatuses.append(status)
    }

    func removeScheduledStatus(_ status: ScheduledStatus) {
        configState?.scheduledStatuses.removeAll { $0.id == status.id }
    }

    func updateScheduledStatus(_ status: ScheduledStatus) {
        if let index = configState?.scheduledStatuses.firstIndex(where: { $0.id == status.id }) {
            configState?.scheduledStatuses[index] = status
        }
    }
}
