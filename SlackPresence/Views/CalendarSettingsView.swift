import SwiftUI
import EventKit

private let slackEmojiDisplay: [(code: String, display: String)] = [
    (":headphones:", "\u{1F3A7}"),
    (":calendar:", "\u{1F4C5}"),
    (":spiral_calendar_pad:", "\u{1F5D3}"),
    (":busts_in_silhouette:", "\u{1F465}"),
]

private let oooEmojiDisplay: [(code: String, display: String)] = [
    (":palm_tree:", "\u{1F334}"),
    (":airplane:", "\u{2708}\u{FE0F}"),
    (":house:", "\u{1F3E0}"),
    (":no_bell:", "\u{1F515}"),
]

struct CalendarSettingsContent: View {
    @Bindable var configState: ConfigState

    @State private var calendars: [EKCalendar] = []
    @State private var permissionGranted: Bool = false
    @State private var permissionChecked: Bool = false
    @State private var isSyncing: Bool = false
    private let intervalOptions = [5, 10, 15, 30]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Enable toggle
                Toggle("Enable calendar sync", isOn: $configState.calendarSyncEnabled)
                    .onChange(of: configState.calendarSyncEnabled) { _, newValue in
                        ScheduleManager.shared.updateCalendarSync(enabled: newValue)
                        ScheduleManager.shared.saveConfig()
                        if newValue {
                            checkPermissionAndLoadCalendars()
                        }
                    }

                if configState.calendarSyncEnabled {
                    Divider()

                    // Permission section
                    permissionSection

                    if permissionGranted {
                        Divider()
                        calendarListSection
                        Divider()
                        availabilitySection
                        Divider()
                        meetingStatusSection
                        Divider()
                        oooSection
                        Divider()
                        syncSettingsSection
                    }
                }
            }
            .padding(20)
        }
        .onAppear {
            checkPermissionAndLoadCalendars()
        }
    }

    // MARK: - Permission

    @ViewBuilder
    private var permissionSection: some View {
        if !permissionChecked {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking calendar access...")
                    .foregroundColor(.secondary)
            }
        } else if permissionGranted {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("Calendar access granted")
                    .foregroundColor(.secondary)
            }
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text("Calendar access required")
                        .font(.headline)
                }
                Text("SlackPresence needs access to your calendars to detect meetings.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Button("Grant Calendar Access") {
                    Task {
                        let granted = await CalendarMonitor.shared.requestAccess()
                        await MainActor.run {
                            permissionGranted = granted
                            if granted { loadCalendars() }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Calendar List

    private var calendarListSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Monitored Calendars")
                .font(.headline)
            Text("Select which calendars to check for meetings")
                .font(.caption)
                .foregroundColor(.secondary)

            if calendars.isEmpty {
                Text("No calendars found")
                    .foregroundColor(.secondary)
                    .italic()
            } else {
                VStack(spacing: 4) {
                    ForEach(calendars, id: \.calendarIdentifier) { calendar in
                        calendarRow(calendar)
                    }
                }
            }
        }
    }

    private func calendarRow(_ calendar: EKCalendar) -> some View {
        let isSelected = configState.selectedCalendarIDs.contains(calendar.calendarIdentifier)
        return HStack(spacing: 8) {
            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                .foregroundColor(isSelected ? .accentColor : .secondary)
            Circle()
                .fill(Color(cgColor: calendar.cgColor))
                .frame(width: 10, height: 10)
            Text(calendar.title)
            Spacer()
            Text(calendar.source.title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelected {
                configState.selectedCalendarIDs.remove(calendar.calendarIdentifier)
            } else {
                configState.selectedCalendarIDs.insert(calendar.calendarIdentifier)
            }
            ScheduleManager.shared.updateSelectedCalendars(configState.selectedCalendarIDs)
            ScheduleManager.shared.saveConfig()
        }
        .padding(.vertical, 4)
    }

    // MARK: - Meeting Status

    private var meetingStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Meeting Status")
                .font(.headline)

            Text("Emoji")
                .font(.subheadline)
                .foregroundColor(.secondary)
            HStack(spacing: 6) {
                ForEach(slackEmojiDisplay, id: \.code) { option in
                    Button(option.display) {
                        configState.meetingEmoji = option.code
                        ScheduleManager.shared.saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .tint(configState.meetingEmoji == option.code ? .accentColor : .secondary)
                }
            }
            TextField("Custom emoji code", text: $configState.meetingEmoji)
                .textFieldStyle(.roundedBorder)
                .onChange(of: configState.meetingEmoji) { _, _ in
                    ScheduleManager.shared.saveConfig()
                }

            Text("Status text")
                .font(.subheadline)
                .foregroundColor(.secondary)
            TextField("In a meeting", text: $configState.meetingStatusText)
                .textFieldStyle(.roundedBorder)
                .onChange(of: configState.meetingStatusText) { _, _ in
                    ScheduleManager.shared.saveConfig()
                }
        }
    }

    // MARK: - Availability Triggers

    private var availabilitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Availability Triggers")
                .font(.headline)
            Text("Which calendar event types trigger meeting status")
                .font(.caption)
                .foregroundColor(.secondary)

            Toggle("Busy events", isOn: $configState.triggerOnBusy)
                .onChange(of: configState.triggerOnBusy) { _, _ in
                    ScheduleManager.shared.updateAvailabilityFilter(
                        busy: configState.triggerOnBusy,
                        tentative: configState.triggerOnTentative,
                        free: configState.triggerOnFree
                    )
                    ScheduleManager.shared.saveConfig()
                }
            Toggle("Tentative events", isOn: $configState.triggerOnTentative)
                .onChange(of: configState.triggerOnTentative) { _, _ in
                    ScheduleManager.shared.updateAvailabilityFilter(
                        busy: configState.triggerOnBusy,
                        tentative: configState.triggerOnTentative,
                        free: configState.triggerOnFree
                    )
                    ScheduleManager.shared.saveConfig()
                }
            Toggle("Free events", isOn: $configState.triggerOnFree)
                .onChange(of: configState.triggerOnFree) { _, _ in
                    ScheduleManager.shared.updateAvailabilityFilter(
                        busy: configState.triggerOnBusy,
                        tentative: configState.triggerOnTentative,
                        free: configState.triggerOnFree
                    )
                    ScheduleManager.shared.saveConfig()
                }
        }
    }

    // MARK: - Out of Office

    private var oooSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Out of Office")
                .font(.headline)

            Toggle("Detect out of office events", isOn: $configState.oooEnabled)
                .onChange(of: configState.oooEnabled) { _, _ in
                    ScheduleManager.shared.saveConfig()
                }

            if configState.oooEnabled {
                Text("Sets Away presence and custom status for events marked as 'Out of Office' in your calendar")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("Emoji")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                HStack(spacing: 6) {
                    ForEach(oooEmojiDisplay, id: \.code) { option in
                        Button(option.display) {
                            configState.oooEmoji = option.code
                            ScheduleManager.shared.saveConfig()
                        }
                        .buttonStyle(.bordered)
                        .tint(configState.oooEmoji == option.code ? .accentColor : .secondary)
                    }
                }
                TextField("Custom emoji code", text: $configState.oooEmoji)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: configState.oooEmoji) { _, _ in
                        ScheduleManager.shared.saveConfig()
                    }

                Text("Status text")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                TextField("Out of office", text: $configState.oooStatusText)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: configState.oooStatusText) { _, _ in
                        ScheduleManager.shared.saveConfig()
                    }

                Toggle("Pause notifications during OOO", isOn: $configState.oooPauseNotifications)
                    .onChange(of: configState.oooPauseNotifications) { _, _ in
                        ScheduleManager.shared.saveConfig()
                    }
            }
        }
    }

    // MARK: - Sync Settings

    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Settings")
                .font(.headline)

            Picker("Check calendar every", selection: $configState.calendarSyncIntervalMinutes) {
                ForEach(intervalOptions, id: \.self) { minutes in
                    Text("\(minutes) minutes").tag(minutes)
                }
            }
            .onChange(of: configState.calendarSyncIntervalMinutes) { _, newValue in
                ScheduleManager.shared.updateCalendarSyncInterval(minutes: newValue)
                ScheduleManager.shared.saveConfig()
            }

            HStack {
                Button {
                    isSyncing = true
                    ScheduleManager.shared.syncCalendarNow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        isSyncing = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        if isSyncing {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("Sync Now")
                    }
                }
                .disabled(isSyncing)
            }

            Text("Also updates immediately when calendar changes are detected")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Helpers

    private func checkPermissionAndLoadCalendars() {
        let status = CalendarMonitor.shared.authorizationStatus
        permissionGranted = status == .fullAccess
        permissionChecked = true
        if permissionGranted {
            loadCalendars()
        }
    }

    private func loadCalendars() {
        calendars = CalendarMonitor.shared.getAvailableCalendars()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Onboarding Calendar Step

// MARK: - Onboarding Step 1: Calendar Enable + Selection

struct CalendarStepView: View {
    @Bindable var configState: ConfigState

    @State private var calendars: [EKCalendar] = []
    @State private var permissionGranted: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Fixed header
            VStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                    .padding(.top, 16)

                Text("Calendar Integration")
                    .font(.title2)
                    .fontWeight(.bold)

                Text("Automatically set your Slack status when you're in a meeting")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)

                Toggle("Enable calendar sync", isOn: $configState.calendarSyncEnabled)
                    .padding(.horizontal, 40)
                    .onChange(of: configState.calendarSyncEnabled) { _, newValue in
                        ScheduleManager.shared.updateCalendarSync(enabled: newValue)
                        ScheduleManager.shared.saveConfig()
                        if newValue { requestAccessAndLoad() }
                    }
            }
            .padding(.bottom, 12)

            // Scrollable content area
            if configState.calendarSyncEnabled {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        // Outlook sync guide
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("To sync your Outlook calendar with macOS:")
                                    .font(.caption)
                                Group {
                                    Text("1. Open **System Settings** > **Internet Accounts**")
                                    Text("2. Click **Add Account** > **Microsoft Exchange**")
                                    Text("3. Sign in with your work email")
                                    Text("4. Keep **Calendars** enabled in the sync options")
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 4)

                                Divider().padding(.vertical, 4)

                                HStack(alignment: .top, spacing: 6) {
                                    Image(systemName: "bell.slash")
                                        .foregroundColor(.orange)
                                        .font(.caption)
                                    Text("Tip: Disable notifications in the macOS Calendar app to avoid duplicate alerts from both Outlook and Calendar.")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            .padding(.top, 6)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "questionmark.circle")
                                    .foregroundColor(.accentColor)
                                Text("How to sync Outlook with macOS Calendar")
                                    .font(.caption)
                            }
                        }

                        if !permissionGranted {
                            Button("Grant Calendar Access") {
                                requestAccessAndLoad()
                            }
                        } else if calendars.isEmpty {
                            Text("No calendars found")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Select calendars to monitor for meetings")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            VStack(spacing: 4) {
                                ForEach(calendars, id: \.calendarIdentifier) { calendar in
                                    let isSelected = configState.selectedCalendarIDs.contains(calendar.calendarIdentifier)
                                    HStack(spacing: 8) {
                                        Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                            .foregroundColor(isSelected ? .accentColor : .secondary)
                                        Circle()
                                            .fill(Color(cgColor: calendar.cgColor))
                                            .frame(width: 10, height: 10)
                                        Text(calendar.title)
                                            .lineLimit(1)
                                        Spacer()
                                        Text(calendar.source.title)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                            .lineLimit(1)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        if isSelected {
                                            configState.selectedCalendarIDs.remove(calendar.calendarIdentifier)
                                        } else {
                                            configState.selectedCalendarIDs.insert(calendar.calendarIdentifier)
                                        }
                                        ScheduleManager.shared.updateSelectedCalendars(configState.selectedCalendarIDs)
                                        ScheduleManager.shared.saveConfig()
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 40)
                    .padding(.bottom, 16)
                }
            } else {
                Spacer()
            }
        }
        .onAppear {
            let status = CalendarMonitor.shared.authorizationStatus
            permissionGranted = status == .fullAccess
            if permissionGranted { loadCalendars() }
        }
    }

    private func requestAccessAndLoad() {
        Task {
            let granted = await CalendarMonitor.shared.requestAccess()
            await MainActor.run {
                permissionGranted = granted
                if granted { loadCalendars() }
            }
        }
    }

    private func loadCalendars() {
        calendars = CalendarMonitor.shared.getAvailableCalendars()
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }
}

// MARK: - Onboarding Step 2: Meeting Status Configuration

struct CalendarConfigStepView: View {
    @Bindable var configState: ConfigState

    private let intervalOptions = [5, 10, 15, 30]

    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "person.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Meeting Status")
                .font(.title2)
                .fontWeight(.bold)

            Text("Configure how your Slack status appears during meetings")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 16) {
                // Meeting emoji
                VStack(alignment: .leading, spacing: 6) {
                    Text("Meeting emoji")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    HStack(spacing: 6) {
                        ForEach(slackEmojiDisplay, id: \.code) { option in
                            Button {
                                configState.meetingEmoji = option.code
                                ScheduleManager.shared.saveConfig()
                            } label: {
                                Text(option.display)
                                    .font(.title3)
                            }
                            .buttonStyle(.bordered)
                            .tint(configState.meetingEmoji == option.code ? .accentColor : .secondary)
                        }
                    }
                    TextField("Custom Slack emoji code", text: $configState.meetingEmoji)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: configState.meetingEmoji) { _, _ in
                            ScheduleManager.shared.saveConfig()
                        }
                }

                // Status text
                VStack(alignment: .leading, spacing: 6) {
                    Text("Status text")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    TextField("In a meeting", text: $configState.meetingStatusText)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: configState.meetingStatusText) { _, _ in
                            ScheduleManager.shared.saveConfig()
                        }
                }

                // Sync interval
                VStack(alignment: .leading, spacing: 6) {
                    Picker("Check calendar every", selection: $configState.calendarSyncIntervalMinutes) {
                        ForEach(intervalOptions, id: \.self) { minutes in
                            Text("\(minutes) minutes").tag(minutes)
                        }
                    }
                    .onChange(of: configState.calendarSyncIntervalMinutes) { _, newValue in
                        ScheduleManager.shared.updateCalendarSyncInterval(minutes: newValue)
                        ScheduleManager.shared.saveConfig()
                    }
                    Text("How often SlackPresence reads your macOS calendar for upcoming meetings")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Divider()

                // Out of Office
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Set status for out of office events", isOn: $configState.oooEnabled)
                        .onChange(of: configState.oooEnabled) { _, _ in
                            ScheduleManager.shared.saveConfig()
                        }

                    if configState.oooEnabled {
                        Text("OOO emoji")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        HStack(spacing: 6) {
                            ForEach(oooEmojiDisplay, id: \.code) { option in
                                Button {
                                    configState.oooEmoji = option.code
                                    ScheduleManager.shared.saveConfig()
                                } label: {
                                    Text(option.display)
                                        .font(.title3)
                                }
                                .buttonStyle(.bordered)
                                .tint(configState.oooEmoji == option.code ? .accentColor : .secondary)
                            }
                        }
                        TextField("Custom Slack emoji code", text: $configState.oooEmoji)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: configState.oooEmoji) { _, _ in
                                ScheduleManager.shared.saveConfig()
                            }

                        TextField("Out of office", text: $configState.oooStatusText)
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: configState.oooStatusText) { _, _ in
                                ScheduleManager.shared.saveConfig()
                            }

                        Toggle("Pause notifications during OOO", isOn: $configState.oooPauseNotifications)
                            .onChange(of: configState.oooPauseNotifications) { _, _ in
                                ScheduleManager.shared.saveConfig()
                            }
                    }
                }
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
    }
}
