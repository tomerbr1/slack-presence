import SwiftUI
import EventKit

struct CalendarSettingsContent: View {
    @Bindable var configState: ConfigState

    @State private var calendars: [EKCalendar] = []
    @State private var permissionGranted: Bool = false
    @State private var permissionChecked: Bool = false
    @State private var isSyncing: Bool = false

    private let emojiOptions = [":headphones:", ":calendar:", ":spiral_calendar_pad:", ":busts_in_silhouette:"]
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
                        meetingStatusSection
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
                ForEach(emojiOptions, id: \.self) { emoji in
                    Button(emoji) {
                        configState.meetingEmoji = emoji
                        ScheduleManager.shared.saveConfig()
                    }
                    .buttonStyle(.bordered)
                    .tint(configState.meetingEmoji == emoji ? .accentColor : .secondary)
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

    // MARK: - Sync Settings

    private var syncSettingsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sync Settings")
                .font(.headline)

            Picker("Sync interval", selection: $configState.calendarSyncIntervalMinutes) {
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

struct CalendarStepView: View {
    @Bindable var configState: ConfigState

    @State private var calendars: [EKCalendar] = []
    @State private var permissionGranted: Bool = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "calendar")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Calendar Integration")
                .font(.title2)
                .fontWeight(.bold)

            Text("Automatically set your Slack status when you're in a meeting")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            VStack(alignment: .leading, spacing: 12) {
                Toggle("Enable calendar sync", isOn: $configState.calendarSyncEnabled)
                    .onChange(of: configState.calendarSyncEnabled) { _, newValue in
                        ScheduleManager.shared.updateCalendarSync(enabled: newValue)
                        ScheduleManager.shared.saveConfig()
                        if newValue { requestAccessAndLoad() }
                    }

                if configState.calendarSyncEnabled {
                    if !permissionGranted {
                        Button("Grant Calendar Access") {
                            requestAccessAndLoad()
                        }
                    } else if calendars.isEmpty {
                        Text("No calendars found")
                            .foregroundColor(.secondary)
                    } else {
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
                                .padding(.vertical, 2)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 40)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .foregroundColor(.secondary)
                Text("You can configure meeting emoji and sync interval in Settings")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 40)

            Spacer()
        }
        .padding()
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
