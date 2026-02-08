import SwiftUI
import ServiceManagement

// MARK: - Settings View

struct SettingsView: View {
    @Bindable var appState: AppState
    @Bindable var configState: ConfigState

    @State private var selectedTab: SettingsTab = .connection

    enum SettingsTab: String, CaseIterable {
        case connection = "Connection"
        case behavior = "Behavior"
        case devices = "Devices"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab Picker
            Picker("", selection: $selectedTab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            // Tab Content
            Group {
                switch selectedTab {
                case .connection:
                    ConnectionTab(appState: appState)
                case .behavior:
                    BehaviorTab(appState: appState, configState: configState)
                case .devices:
                    DevicesTab(configState: configState)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(width: 420, height: 620)
    }
}

// MARK: - Connection Tab

struct ConnectionTab: View {
    @Bindable var appState: AppState

    @State private var token: String = ""
    @State private var cookie: String = ""
    @State private var isTesting: Bool = false
    @State private var connectionStatus: ConnectionStatus = .unknown
    @State private var errorMessage: String?

    enum ConnectionStatus {
        case unknown, testing, connected, failed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status Banner
            HStack(spacing: 10) {
                statusIcon
                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(statusBackground)
            .cornerRadius(10)

            // Credentials Form
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("API Token")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("xoxc-...", text: $token)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Session Cookie")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    SecureField("d cookie value", text: $cookie)
                        .textFieldStyle(.roundedBorder)
                }
            }

            // Actions
            HStack {
                Button("How to get API Token and Session Cookie") {
                    NotificationCenter.default.post(name: .openTokenHelp, object: nil)
                }
                .buttonStyle(.link)
                .font(.callout)

                Spacer()

                Button("Test") {
                    testConnection()
                }
                .disabled(token.isEmpty || cookie.isEmpty || isTesting)

                Button("Save") {
                    saveCredentials()
                }
                .buttonStyle(.borderedProminent)
                .disabled(token.isEmpty || cookie.isEmpty)
            }

            Spacer()
        }
        .padding(20)
        .onAppear { loadCredentials() }
    }

    // MARK: - Status Display

    private var statusIcon: some View {
        Group {
            switch connectionStatus {
            case .unknown:
                Image(systemName: "circle.dashed")
                    .foregroundColor(.secondary)
            case .testing:
                ProgressView()
                    .scaleEffect(0.8)
            case .connected:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            case .failed:
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
            }
        }
        .font(.title2)
        .frame(width: 28)
    }

    private var statusTitle: String {
        switch connectionStatus {
        case .unknown: return "Not Connected"
        case .testing: return "Testing..."
        case .connected: return "Connected"
        case .failed: return "Connection Failed"
        }
    }

    private var statusSubtitle: String {
        switch connectionStatus {
        case .unknown: return "Enter your Slack credentials"
        case .testing: return "Verifying with Slack..."
        case .connected: return "Ready to manage your presence"
        case .failed: return errorMessage ?? "Check your token and cookie"
        }
    }

    private var statusBackground: Color {
        switch connectionStatus {
        case .unknown: return Color(.controlBackgroundColor)
        case .testing: return Color(.controlBackgroundColor)
        case .connected: return Color.green.opacity(0.1)
        case .failed: return Color.red.opacity(0.1)
        }
    }

    // MARK: - Actions

    private func loadCredentials() {
        if let creds = ConfigManager.shared.loadCredentials() {
            token = creds.token
            cookie = creds.cookie
            if creds.isValid {
                connectionStatus = .connected
            }
        }
    }

    /// Cleans credential value by trimming whitespace and surrounding quotes
    private func cleanCredential(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove surrounding quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned
    }

    private func saveCredentials() {
        let creds = SlackCredentials(token: cleanCredential(token), cookie: cleanCredential(cookie))
        errorMessage = nil
        do {
            try ConfigManager.shared.saveCredentials(creds)
            SlackClient.shared.updateCredentials(creds)
            // Verify credentials work before marking as connected
            connectionStatus = .testing
            isTesting = true
            Task {
                do {
                    let success = try await SlackClient.shared.testConnection(with: creds)
                    await MainActor.run {
                        if success {
                            appState.hasValidCredentials = true
                            connectionStatus = .connected
                            errorMessage = nil
                        } else {
                            appState.hasValidCredentials = false
                            connectionStatus = .failed
                            errorMessage = "Invalid credentials"
                        }
                        isTesting = false
                    }
                } catch {
                    await MainActor.run {
                        appState.hasValidCredentials = false
                        connectionStatus = .failed
                        errorMessage = error.localizedDescription
                        isTesting = false
                    }
                }
            }
        } catch {
            connectionStatus = .failed
            errorMessage = error.localizedDescription
        }
    }

    private func testConnection() {
        connectionStatus = .testing
        isTesting = true
        errorMessage = nil

        let creds = SlackCredentials(token: cleanCredential(token), cookie: cleanCredential(cookie))

        Task {
            do {
                let success = try await SlackClient.shared.testConnection(with: creds)
                await MainActor.run {
                    if success {
                        connectionStatus = .connected
                        errorMessage = nil
                    } else {
                        connectionStatus = .failed
                        errorMessage = "Invalid credentials"
                    }
                    isTesting = false
                }
            } catch {
                await MainActor.run {
                    connectionStatus = .failed
                    errorMessage = error.localizedDescription
                    isTesting = false
                }
            }
        }
    }
}

// MARK: - Behavior Tab

struct BehaviorTab: View {
    @Bindable var appState: AppState
    @Bindable var configState: ConfigState

    @State private var isRefreshingMic: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Call Detection
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "mic.fill")
                        .foregroundColor(.purple)
                    Text("Call Detection")
                        .font(.headline)
                }

                Toggle("Show :headphones: during calls", isOn: $configState.callDetectionEnabled)
                    .onChange(of: configState.callDetectionEnabled) { _, newValue in
                        ScheduleManager.shared.updateCallDetection(enabled: newValue)
                        ScheduleManager.shared.saveConfig()
                        if newValue { refreshMicStatus() }
                    }

                if configState.callDetectionEnabled {
                    HStack(spacing: 16) {
                        StatusPill(label: "Mic", isActive: appState.micActive, activeText: "Active", inactiveText: "Idle")
                        if appState.manualInCallOverride == true {
                            Text("(Manual)")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                        Spacer()
                        Button(action: refreshMicStatus) {
                            Image(systemName: isRefreshingMic ? "arrow.clockwise" : "arrow.clockwise")
                                .rotationEffect(.degrees(isRefreshingMic ? 360 : 0))
                                .animation(isRefreshingMic ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshingMic)
                        }
                        .buttonStyle(.borderless)
                        .disabled(isRefreshingMic)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)

                    // Detection timing settings
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Call start delay:")
                                .font(.caption)
                            Stepper("\(configState.callStartDelay)s", value: $configState.callStartDelay, in: 1...30)
                                .font(.caption)
                                .onChange(of: configState.callStartDelay) { _, newValue in
                                    MicMonitor.shared.callStartDelay = TimeInterval(newValue)
                                    ScheduleManager.shared.saveConfig()
                                }
                        }
                        HStack {
                            Text("Call end delay:")
                                .font(.caption)
                            Stepper("\(configState.callEndDelay)s", value: $configState.callEndDelay, in: 1...30)
                                .font(.caption)
                                .onChange(of: configState.callEndDelay) { _, newValue in
                                    MicMonitor.shared.callEndDelay = TimeInterval(newValue)
                                    ScheduleManager.shared.saveConfig()
                                }
                        }
                        Text("Time to wait before confirming call state changes")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(Color(.controlBackgroundColor).opacity(0.5))
                    .cornerRadius(8)
                }
            }

            Divider()

            // DND Settings
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "bell.slash.fill")
                        .foregroundColor(.orange)
                    Text("Do Not Disturb")
                        .font(.headline)
                }

                Toggle("Pause notifications when away", isOn: $configState.pauseNotificationsWhenAway)
                    .onChange(of: configState.pauseNotificationsWhenAway) { _, newValue in
                        ScheduleManager.shared.updatePauseNotifications(enabled: newValue)
                        ScheduleManager.shared.saveConfig()
                    }

                Text("Automatically enables DND during your scheduled away hours")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Divider()

            // Launch at Login
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "power")
                        .foregroundColor(.blue)
                    Text("Startup")
                        .font(.headline)
                }

                LaunchAtLoginToggle(showIcon: false)
            }

            Divider()

            // Current Status
            HStack(spacing: 12) {
                Image(systemName: appState.menuBarIcon)
                    .font(.title)
                    .foregroundColor(appState.menuBarIconColor)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(appState.statusText)
                            .font(.subheadline)
                            .fontWeight(.medium)
                        if appState.isDNDActive {
                            Text("• Notifications Paused")
                                .font(.subheadline)
                                .foregroundColor(.orange)
                        }
                    }
                    if let lastUpdate = appState.lastUpdate {
                        Text("Updated \(lastUpdate.formatted(date: .omitted, time: .shortened))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                if appState.isDNDActive {
                    Text("DND")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.2))
                        .foregroundColor(.orange)
                        .cornerRadius(4)
                }
            }
            .padding(12)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)

            Spacer()
        }
        .padding(20)
        .onAppear {
            if configState.callDetectionEnabled {
                refreshMicStatus()
            }
        }
    }

    private func refreshMicStatus() {
        isRefreshingMic = true
        let result = MicMonitor.shared.forceCheck()
        appState.micActive = result.micActive
        appState.isInCall = result.inCall

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshingMic = false
        }
    }
}

// MARK: - Devices Tab

struct DevicesTab: View {
    @Bindable var configState: ConfigState

    @State private var devices: [AudioDeviceInfo] = []
    @State private var isRefreshing: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "mic.fill")
                    .foregroundColor(.purple)
                Text("Input Devices")
                    .font(.headline)
                Spacer()
                Button(action: refreshDevices) {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                        .animation(isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
            }

            Text("Enable devices you want to use for call detection. Disabled devices will be ignored even when active.")
                .font(.caption)
                .foregroundColor(.secondary)

            // Device List
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(devices) { device in
                        SharedDeviceRow(
                            device: device,
                            isEnabled: !configState.disabledDeviceUIDs.contains(device.uid),
                            onToggle: { enabled in
                                toggleDevice(device: device, enabled: enabled)
                            }
                        )
                    }

                    if devices.isEmpty {
                        Text("No input devices found")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding()
                    }
                }
            }

            // Legend
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Circle().fill(Color.green).frame(width: 8, height: 8)
                    Text("Active")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Circle().fill(Color.gray.opacity(0.4)).frame(width: 8, height: 8)
                    Text("Idle")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Circle().fill(Color.orange.opacity(0.6)).frame(width: 8, height: 8)
                    Text("Auto-ignored")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Text("Auto-ignored devices are virtual audio devices or known false-positive sources.")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(20)
        .onAppear { refreshDevices() }
    }

    private func refreshDevices() {
        isRefreshing = true
        devices = MicMonitor.shared.getAllDevicesInfo()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            isRefreshing = false
        }
    }

    private func toggleDevice(device: AudioDeviceInfo, enabled: Bool) {
        if enabled {
            configState.disabledDeviceUIDs.remove(device.uid)
            MicMonitor.shared.enableDevice(uid: device.uid)
        } else {
            configState.disabledDeviceUIDs.insert(device.uid)
            MicMonitor.shared.disableDevice(uid: device.uid)
        }
        ScheduleManager.shared.saveConfig()
        // Refresh to update display
        devices = MicMonitor.shared.getAllDevicesInfo()
    }
}

// MARK: - Status Pill Component

struct StatusPill: View {
    let label: String
    let isActive: Bool
    let activeText: String
    let inactiveText: String

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isActive ? Color.green : Color.gray.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(isActive ? activeText : inactiveText)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

#Preview {
    SettingsView(appState: AppState(), configState: ConfigState())
}
