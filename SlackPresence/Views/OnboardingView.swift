import SwiftUI
import AVFoundation
import ServiceManagement

// MARK: - Onboarding Step Enum

enum OnboardingStep: Int, CaseIterable {
    case welcome = 0
    case credentials
    case permissions
    case devices
    case schedule
    case finish

    var title: String {
        switch self {
        case .welcome: return "Welcome"
        case .credentials: return "Connect to Slack"
        case .permissions: return "Permissions"
        case .devices: return "Device Selection"
        case .schedule: return "Schedule"
        case .finish: return "All Set!"
        }
    }
}

// MARK: - Main Onboarding View

struct OnboardingView: View {
    @Bindable var appState: AppState
    @Bindable var configState: ConfigState
    var onComplete: () -> Void

    @State private var currentStep: OnboardingStep = .welcome
    @State private var dontShowAgain: Bool = true

    var body: some View {
        VStack(spacing: 0) {
            // Progress dots
            OnboardingProgressDots(currentStep: currentStep)
                .padding(.top, 20)
                .padding(.bottom, 16)

            // Step content
            Group {
                switch currentStep {
                case .welcome:
                    WelcomeStepView()
                case .credentials:
                    CredentialsStepView(appState: appState)
                case .permissions:
                    PermissionsStepView()
                case .devices:
                    DevicesStepView(configState: configState)
                case .schedule:
                    ScheduleStepView(configState: configState)
                case .finish:
                    FinishStepView(configState: configState, dontShowAgain: $dontShowAgain)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            ))
            .animation(.easeInOut(duration: 0.3), value: currentStep)

            Divider()

            // Navigation buttons
            HStack {
                if currentStep != .welcome {
                    Button("Back") {
                        withAnimation {
                            if let previous = OnboardingStep(rawValue: currentStep.rawValue - 1) {
                                currentStep = previous
                            }
                        }
                    }
                }

                Spacer()

                if currentStep == .credentials {
                    Button("Skip for Now") {
                        withAnimation {
                            currentStep = .permissions
                        }
                    }
                    .foregroundColor(.secondary)
                }

                if currentStep == .finish {
                    Button("Start Using App") {
                        completeOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button("Continue") {
                        withAnimation {
                            if let next = OnboardingStep(rawValue: currentStep.rawValue + 1) {
                                currentStep = next
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
        }
        .frame(width: 520, height: 650)
    }

    private func completeOnboarding() {
        if dontShowAgain {
            configState.hasCompletedOnboarding = true
            ScheduleManager.shared.saveConfig()
        }
        onComplete()
    }
}

// MARK: - Progress Dots

struct OnboardingProgressDots: View {
    let currentStep: OnboardingStep

    var body: some View {
        HStack(spacing: 8) {
            ForEach(OnboardingStep.allCases, id: \.rawValue) { step in
                Circle()
                    .fill(step == currentStep ? Color.accentColor : Color.gray.opacity(0.3))
                    .frame(width: step == currentStep ? 10 : 8, height: step == currentStep ? 10 : 8)
                    .scaleEffect(step == currentStep ? 1.0 : 0.8)
                    .animation(.spring(response: 0.3, dampingFraction: 0.7), value: currentStep)
            }
        }
    }
}

// MARK: - Step 1: Welcome

struct WelcomeStepView: View {
    @State private var iconScale: CGFloat = 0.8
    @State private var iconOpacity: Double = 0

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // App icon with animation
            Image(systemName: "clock.badge.checkmark.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue, .green)
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .onAppear {
                    withAnimation(.spring(response: 0.6, dampingFraction: 0.6)) {
                        iconScale = 1.0
                        iconOpacity = 1.0
                    }
                }

            Text("Welcome to SlackPresence")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("Automatically manage your Slack presence based on your schedule")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Feature highlights
            VStack(alignment: .leading, spacing: 12) {
                OnboardingFeatureRow(
                    icon: "sun.max.fill",
                    iconColor: .green,
                    title: "Work Hours",
                    description: "Automatically set to Active during your work schedule"
                )

                OnboardingFeatureRow(
                    icon: "moon.fill",
                    iconColor: .gray,
                    title: "After Hours",
                    description: "Switch to Away when your workday ends"
                )

                OnboardingFeatureRow(
                    icon: "headphones",
                    iconColor: .purple,
                    title: "Call Detection",
                    description: "Show :headphones: status when you're in a meeting"
                )

                OnboardingFeatureRow(
                    icon: "bell.slash.fill",
                    iconColor: .orange,
                    title: "Do Not Disturb",
                    description: "Optionally pause notifications during away hours"
                )
            }
            .padding(.horizontal, 40)
            .padding(.top, 20)

            Spacer()
        }
        .padding()
    }
}

// MARK: - Step 2: Credentials

struct CredentialsStepView: View {
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
        VStack(spacing: 20) {
            // Header
            Image(systemName: "link.badge.plus")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Connect to Slack")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Enter your Slack credentials to enable presence management")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

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
            .padding(.horizontal, 30)

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
            .padding(.horizontal, 30)

            // Actions
            HStack {
                Button("How to get credentials") {
                    NotificationCenter.default.post(name: .openTokenHelp, object: nil)
                }
                .buttonStyle(.link)
                .font(.callout)

                Spacer()

                Button("Test Connection") {
                    testConnection()
                }
                .disabled(token.isEmpty || cookie.isEmpty || isTesting)

                Button("Save") {
                    saveCredentials()
                }
                .disabled(token.isEmpty || cookie.isEmpty)
            }
            .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 20)
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

    private func saveCredentials() {
        let creds = SlackCredentials(token: token, cookie: cookie)
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

        let creds = SlackCredentials(token: token, cookie: cookie)

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

// MARK: - Step 3: Permissions

struct PermissionsStepView: View {
    @State private var micPermissionStatus: AVAuthorizationStatus = .notDetermined

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "mic.fill")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("Microphone Permission")
                .font(.title2)
                .fontWeight(.semibold)

            Text("SlackPresence uses microphone access to detect when you're in a call")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Privacy card
            OnboardingInfoCard(
                icon: "lock.shield.fill",
                iconColor: .blue,
                title: "Your Privacy is Protected",
                description: "We never record audio or listen to your conversations. We only check if the microphone is active to detect calls."
            )
            .padding(.horizontal, 30)

            // Permission status
            HStack(spacing: 12) {
                Image(systemName: permissionIcon)
                    .font(.title2)
                    .foregroundColor(permissionColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(permissionTitle)
                        .font(.headline)
                    Text(permissionSubtitle)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if micPermissionStatus == .notDetermined || micPermissionStatus == .denied {
                    Button("Grant Access") {
                        requestPermission()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 30)

            Spacer()
        }
        .padding()
        .onAppear {
            micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        }
    }

    private var permissionIcon: String {
        switch micPermissionStatus {
        case .authorized: return "checkmark.circle.fill"
        case .denied, .restricted: return "xmark.circle.fill"
        default: return "questionmark.circle"
        }
    }

    private var permissionColor: Color {
        switch micPermissionStatus {
        case .authorized: return .green
        case .denied, .restricted: return .red
        default: return .orange
        }
    }

    private var permissionTitle: String {
        switch micPermissionStatus {
        case .authorized: return "Permission Granted"
        case .denied: return "Permission Denied"
        case .restricted: return "Permission Restricted"
        default: return "Permission Required"
        }
    }

    private var permissionSubtitle: String {
        switch micPermissionStatus {
        case .authorized: return "Call detection is ready to use"
        case .denied: return "Open System Settings to enable"
        case .restricted: return "Your device restricts this permission"
        default: return "Click to enable call detection"
        }
    }

    private func requestPermission() {
        if micPermissionStatus == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
        } else {
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async {
                    micPermissionStatus = AVCaptureDevice.authorizationStatus(for: .audio)
                }
            }
        }
    }
}

// MARK: - Step 4: Devices

struct DevicesStepView: View {
    @Bindable var configState: ConfigState

    @State private var devices: [AudioDeviceInfo] = []

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "speaker.wave.2.fill")
                .font(.system(size: 48))
                .foregroundColor(.purple)

            Text("Select Input Devices")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Choose which microphones to monitor for call detection")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Device list
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
            .frame(maxHeight: 200)
            .padding(.horizontal, 30)

            // Tip
            OnboardingInfoCard(
                icon: "lightbulb.fill",
                iconColor: .yellow,
                title: "Tip",
                description: "You can change device selection later in Settings \u{2192} Devices"
            )
            .padding(.horizontal, 30)

            Spacer()
        }
        .padding(.top, 20)
        .onAppear {
            devices = MicMonitor.shared.getAllDevicesInfo()
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
        devices = MicMonitor.shared.getAllDevicesInfo()
    }
}

// MARK: - Step 5: Schedule

struct ScheduleStepView: View {
    @Bindable var configState: ConfigState

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 48))
                .foregroundColor(.blue)

            Text("Your Schedule")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Review your work schedule for presence automation")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Schedule summary
            VStack(alignment: .leading, spacing: 8) {
                ForEach(scheduleSummary, id: \.day) { item in
                    HStack {
                        Text(item.day)
                            .font(.subheadline)
                            .frame(width: 100, alignment: .leading)

                        if item.enabled {
                            Text(item.hours)
                                .font(.subheadline)
                                .foregroundColor(.green)
                        } else {
                            Text("Not managed")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.vertical, 4)
                }
            }
            .padding(16)
            .background(Color(.controlBackgroundColor))
            .cornerRadius(10)
            .padding(.horizontal, 30)

            // Links
            VStack(spacing: 12) {
                Button("Edit Schedule...") {
                    NotificationCenter.default.post(name: .openScheduleEditor, object: nil)
                }
                .buttonStyle(.link)

                Button("Configure Scheduled Statuses...") {
                    NotificationCenter.default.post(name: .openStatusSchedule, object: nil)
                }
                .buttonStyle(.link)
            }

            Spacer()
        }
        .padding(.top, 20)
    }

    private var scheduleSummary: [(day: String, enabled: Bool, hours: String)] {
        let weekdays = [
            (1, "Sunday"),
            (2, "Monday"),
            (3, "Tuesday"),
            (4, "Wednesday"),
            (5, "Thursday"),
            (6, "Friday"),
            (7, "Saturday")
        ]

        return weekdays.map { (num, name) in
            let schedule = configState.schedule.schedule(for: num)
            return (
                day: name,
                enabled: schedule.enabled,
                hours: schedule.enabled ? "\(schedule.activeStart) - \(schedule.activeEnd)" : ""
            )
        }
    }
}

// MARK: - Step 6: Finish

struct FinishStepView: View {
    @Bindable var configState: ConfigState
    @Binding var dontShowAgain: Bool
    @State private var checkmarkScale: CGFloat = 0

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            // Success checkmark with animation
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 72))
                .foregroundColor(.green)
                .scaleEffect(checkmarkScale)
                .onAppear {
                    withAnimation(.spring(response: 0.5, dampingFraction: 0.6)) {
                        checkmarkScale = 1.0
                    }
                }

            Text("You're All Set!")
                .font(.largeTitle)
                .fontWeight(.bold)

            Text("SlackPresence is ready to manage your Slack presence automatically")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Important settings
            VStack(spacing: 8) {
                LaunchAtLoginToggle(showIcon: true, backgroundColor: Color.blue.opacity(0.1))

                HStack(spacing: 12) {
                    Image(systemName: "bell.slash.fill")
                        .font(.title3)
                        .foregroundColor(.orange)
                        .frame(width: 28)

                    Toggle("Pause notifications during away hours", isOn: $configState.pauseNotificationsWhenAway)
                        .onChange(of: configState.pauseNotificationsWhenAway) { _, newValue in
                            ScheduleManager.shared.updatePauseNotifications(enabled: newValue)
                        }
                }
                .padding(12)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(10)
            }
            .padding(.horizontal, 40)

            // Quick reference cards
            VStack(spacing: 10) {
                OnboardingQuickRefCard(
                    icon: "gearshape.fill",
                    iconColor: .gray,
                    title: "Settings",
                    description: "Configure connection, behavior, and devices"
                )

                OnboardingQuickRefCard(
                    icon: "ladybug.fill",
                    iconColor: .purple,
                    title: "Debug",
                    description: "View mic status and troubleshoot call detection"
                )

                OnboardingQuickRefCard(
                    icon: "info.circle.fill",
                    iconColor: .blue,
                    title: "About",
                    description: "Version info and app details"
                )
            }
            .padding(.horizontal, 40)

            Spacer()

            // Don't show again checkbox
            Toggle("Don't show this welcome guide again", isOn: $dontShowAgain)
                .font(.caption)
                .padding(.horizontal, 40)
        }
        .padding()
    }
}

// MARK: - Reusable Components

struct OnboardingFeatureRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct OnboardingInfoCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(iconColor.opacity(0.1))
        .cornerRadius(10)
    }
}

struct OnboardingQuickRefCard: View {
    let icon: String
    let iconColor: Color
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(iconColor)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(12)
        .background(Color(.controlBackgroundColor).opacity(0.5))
        .cornerRadius(8)
    }
}

#Preview {
    OnboardingView(
        appState: AppState(),
        configState: ConfigState(),
        onComplete: {}
    )
}
