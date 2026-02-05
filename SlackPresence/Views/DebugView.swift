import SwiftUI

struct DebugView: View {
    @State private var debugInfo: DebugInfo?
    @State private var lastRefresh: Date?
    @State private var copyFeedback: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundColor(.purple)
                Text("Debug Info")
                    .font(.headline)
                Spacer()
                if let lastRefresh {
                    Text(lastRefresh.formatted(date: .omitted, time: .standard))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            if let info = debugInfo {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        // Mic Permission
                        DebugSection(title: "Mic Permission", icon: "mic.fill") {
                            DebugRow(label: "Status", value: info.micPermissionStatus)
                        }

                        // Input Devices
                        DebugSection(title: "Input Devices (\(info.inputDevices.count))", icon: "speaker.wave.2.fill") {
                            if info.inputDevices.isEmpty {
                                Text("No input devices found")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            } else {
                                ForEach(info.inputDevices) { device in
                                    HStack {
                                        Circle()
                                            .fill(deviceColor(device))
                                            .frame(width: 8, height: 8)
                                        VStack(alignment: .leading, spacing: 1) {
                                            HStack(spacing: 4) {
                                                Text(device.name)
                                                    .font(.caption)
                                                Text("(\(device.transportType))")
                                                    .font(.caption2)
                                                    .foregroundColor(.secondary)
                                            }
                                            if device.isIgnored, let reason = device.ignoreReason {
                                                Text("Ignored: \(reason)")
                                                    .font(.caption2)
                                                    .foregroundColor(.orange)
                                            }
                                        }
                                        Spacer()
                                        Text(device.isRunning ? "Active" : "Idle")
                                            .font(.caption)
                                            .foregroundColor(device.isIgnored ? .secondary : (device.isRunning ? .green : .secondary))
                                    }
                                }
                            }
                        }

                        // Detection State
                        DebugSection(title: "Call Detection", icon: "waveform.path.ecg") {
                            DebugRow(label: "Any Mic Active (physical)", value: info.anyMicActive ? "Yes" : "No", highlight: info.anyMicActive)
                            if let manual = info.manualOverride {
                                DebugRow(label: "Manual Override", value: manual ? "In Call" : "Not In Call", highlight: true)
                            } else {
                                DebugRow(label: "Manual Override", value: "None (auto-detect)")
                            }
                            DebugRow(label: "Current State", value: info.currentCallState ? "IN CALL" : "Not in call", highlight: info.currentCallState)
                        }

                        // Debouncing
                        DebugSection(title: "Debouncing", icon: "timer") {
                            DebugRow(label: "Start Delay", value: "\(info.callStartDelay)s")
                            DebugRow(label: "End Delay", value: "\(info.callEndDelay)s")
                            if let pending = info.pendingCallStart {
                                DebugRow(label: "Pending Start", value: pending, highlight: true)
                            }
                            if let pending = info.pendingCallEnd {
                                DebugRow(label: "Pending End", value: pending, highlight: true)
                            }
                            if let suppression = info.suppressionRemaining, suppression > 0 {
                                DebugRow(label: "Suppressed", value: "\(suppression)s remaining", highlight: true)
                            }
                        }
                    }
                }
            } else {
                Spacer()
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                Spacer()
            }

            // Buttons
            HStack {
                Button(action: copyToClipboard) {
                    Label(copyFeedback ?? "Copy All", systemImage: "doc.on.doc")
                }
                .disabled(debugInfo == nil)

                Spacer()

                Button(action: refresh) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420, height: 620)
        .onAppear { refresh() }
    }

    private func deviceColor(_ device: AudioDeviceInfo) -> Color {
        if device.isIgnored {
            return Color.orange.opacity(0.6)
        }
        return device.isRunning ? Color.green : Color.gray.opacity(0.4)
    }

    private func refresh() {
        debugInfo = MicMonitor.shared.getDebugInfo()
        lastRefresh = Date()
    }

    private func copyToClipboard() {
        let text = MicMonitor.shared.getDebugText()
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        // Show feedback
        copyFeedback = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            copyFeedback = nil
        }
    }
}

// MARK: - Components

struct DebugSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
            VStack(alignment: .leading, spacing: 4) {
                content
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.controlBackgroundColor).opacity(0.5))
            .cornerRadius(8)
        }
    }
}

struct DebugRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .font(.caption)
                .fontWeight(highlight ? .semibold : .regular)
                .foregroundColor(highlight ? .green : .primary)
        }
    }
}

#Preview {
    DebugView()
}
