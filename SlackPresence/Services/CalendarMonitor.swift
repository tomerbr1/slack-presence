import Foundation
import EventKit

final class CalendarMonitor {
    static let shared = CalendarMonitor()

    private let stateLock = NSLock()
    private let eventStore = EKEventStore()
    private var timer: Timer?
    private var isMonitoring = false

    // Callback: (inMeeting, meetingEndDate)
    var onMeetingStateChanged: ((Bool, Date?) -> Void)?

    // Thread-safe state
    private var lastKnownMeetingState: Bool = false
    private var currentMeetingEndDate: Date?
    private var currentMeetingTitle: String?

    // Event cache
    private var cachedEvents: [EKEvent] = []
    private var lastEventFetch: Date = .distantPast
    var eventFetchInterval: TimeInterval = 15 * 60  // Re-fetch events every 15 min

    // Calendar filter
    var selectedCalendarIDs: Set<String> = []

    // Polling interval for meeting state check
    private let calendarCheckInterval: TimeInterval = 60

    private init() {}

    // MARK: - Authorization

    func requestAccess() async -> Bool {
        do {
            return try await eventStore.requestFullAccessToEvents()
        } catch {
            #if DEBUG
            print("Calendar access request failed: \(error)")
            #endif
            return false
        }
    }

    var authorizationStatus: EKAuthorizationStatus {
        EKEventStore.authorizationStatus(for: .event)
    }

    // MARK: - Monitoring

    func startMonitoring() {
        guard !isMonitoring else { return }
        guard authorizationStatus == .fullAccess else {
            #if DEBUG
            print("Calendar access not authorized, skipping monitoring")
            #endif
            return
        }
        isMonitoring = true

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleEventStoreChanged),
            name: .EKEventStoreChanged,
            object: eventStore
        )

        checkMeetingState()

        timer = Timer.scheduledTimer(withTimeInterval: calendarCheckInterval, repeats: true) { [weak self] _ in
            self?.checkMeetingState()
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        isMonitoring = false
        NotificationCenter.default.removeObserver(self, name: .EKEventStoreChanged, object: eventStore)
        onMeetingStateChanged = nil
    }

    // MARK: - Public State Access

    func isInMeeting() -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return lastKnownMeetingState
    }

    func getCurrentMeeting() -> (title: String, endDate: Date)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard lastKnownMeetingState,
              let title = currentMeetingTitle,
              let endDate = currentMeetingEndDate else {
            return nil
        }
        return (title, endDate)
    }

    func getAvailableCalendars() -> [EKCalendar] {
        eventStore.calendars(for: .event)
    }

    func forceSync() {
        stateLock.lock()
        lastEventFetch = .distantPast
        stateLock.unlock()
        checkMeetingState()
    }

    // MARK: - Private

    private func checkMeetingState() {
        stateLock.lock()

        // Refresh cache if stale
        if Date().timeIntervalSince(lastEventFetch) >= eventFetchInterval {
            stateLock.unlock()
            fetchTodayEvents()
            stateLock.lock()
        }

        let now = Date()
        let activeMeeting = cachedEvents.first { event in
            guard !event.isAllDay else { return false }
            guard event.startDate <= now && now < event.endDate else { return false }
            guard selectedCalendarIDs.isEmpty || selectedCalendarIDs.contains(event.calendar.calendarIdentifier) else { return false }
            let availability = event.availability
            return availability == .busy || availability == .tentative
        }

        let inMeeting = activeMeeting != nil
        let changed = inMeeting != lastKnownMeetingState
        lastKnownMeetingState = inMeeting
        currentMeetingEndDate = activeMeeting?.endDate
        currentMeetingTitle = activeMeeting?.title
        let endDate = currentMeetingEndDate
        stateLock.unlock()

        if changed {
            onMeetingStateChanged?(inMeeting, endDate)
        }
    }

    private func fetchTodayEvents() {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: Date())
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return }

        let calendars: [EKCalendar]?
        if selectedCalendarIDs.isEmpty {
            calendars = nil  // All calendars
        } else {
            calendars = eventStore.calendars(for: .event).filter {
                selectedCalendarIDs.contains($0.calendarIdentifier)
            }
        }

        let predicate = eventStore.predicateForEvents(withStart: startOfDay, end: endOfDay, calendars: calendars)
        let events = eventStore.events(matching: predicate)

        stateLock.lock()
        cachedEvents = events
        lastEventFetch = Date()
        stateLock.unlock()
    }

    @objc private func handleEventStoreChanged(_ notification: Notification) {
        stateLock.lock()
        lastEventFetch = .distantPast
        stateLock.unlock()
        checkMeetingState()
    }
}
