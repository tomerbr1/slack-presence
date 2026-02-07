import SwiftUI
import ServiceManagement

// MARK: - Device Row (shared between SettingsView and OnboardingView)

struct SharedDeviceRow: View {
    let device: AudioDeviceInfo
    let isEnabled: Bool
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(device.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("(\(device.transportType))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                if device.isIgnored, let reason = device.ignoreReason, !device.isUserDisabled {
                    Text(reason)
                        .font(.caption2)
                        .foregroundColor(.orange)
                }

                if device.isRunning {
                    Text("Currently active")
                        .font(.caption2)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            if !device.isIgnored || device.isUserDisabled {
                Toggle("", isOn: Binding(
                    get: { isEnabled },
                    set: { onToggle($0) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
            } else {
                Text("Auto")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(4)
            }
        }
        .padding(12)
        .background(backgroundColor)
        .cornerRadius(8)
    }

    private var statusColor: Color {
        if device.isIgnored && !device.isUserDisabled {
            return Color.orange.opacity(0.6)
        }
        if !isEnabled {
            return Color.gray.opacity(0.3)
        }
        return device.isRunning ? Color.green : Color.gray.opacity(0.4)
    }

    private var backgroundColor: Color {
        if !isEnabled {
            return Color(.controlBackgroundColor).opacity(0.3)
        }
        return Color(.controlBackgroundColor).opacity(0.5)
    }
}

// MARK: - Launch at Login Toggle (shared between SettingsView and OnboardingView)

struct LaunchAtLoginToggle: View {
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled
    @State private var message: String? = nil

    /// Optional: different styling for different contexts
    var showIcon: Bool = true
    var backgroundColor: Color? = nil

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                if showIcon {
                    Image(systemName: "power")
                        .font(.title3)
                        .foregroundColor(.blue)
                        .frame(width: 28)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Launch at Login")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Start SlackPresence when you log in")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()

                Toggle("", isOn: $launchAtLogin)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .onChange(of: launchAtLogin) { _, newValue in
                        updateLoginItem(enabled: newValue)
                    }
            }
            .padding(12)
            .background(backgroundColor ?? Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(10)

            if let message = message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(message.starts(with: "Failed") ? .red : .green)
                    .transition(.opacity)
            }
        }
    }

    private func updateLoginItem(enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
                message = "Added to Login Items"
            } else {
                try SMAppService.mainApp.unregister()
                message = "Removed from Login Items"
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                message = nil
            }
        } catch {
            launchAtLogin = !enabled
            message = "Failed: \(error.localizedDescription)"
            #if DEBUG
            print("Failed to update login item: \(error)")
            #endif
        }
    }
}
