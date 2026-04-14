import SwiftUI

struct TroubleshootingView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Troubleshooting")
                    .font(.title2)
                    .fontWeight(.semibold)

                troubleshootingSection(
                    icon: "exclamationmark.triangle",
                    iconColor: .orange,
                    title: "App detects calls when I'm not in one",
                    steps: [
                        "Open Settings > Devices and disable the problematic device",
                        "Increase call start delay in Settings > Behavior (higher = fewer false positives)",
                        "Use menu bar > \"Call Detection\" toggle to disable temporarily"
                    ]
                )

                troubleshootingSection(
                    icon: "calendar.badge.exclamationmark",
                    iconColor: .red,
                    title: "Meeting status not showing",
                    steps: [
                        "Check calendar permissions: System Settings > Privacy & Security > Calendars",
                        "Verify correct calendar is selected in Settings > Calendar",
                        "Meeting must be marked as Busy or Tentative (not Free)",
                        "Use \"Sync Calendar Now\" from menu bar to force refresh"
                    ]
                )

                troubleshootingSection(
                    icon: "arrow.clockwise",
                    iconColor: .blue,
                    title: "Status stuck after meeting or call",
                    steps: [
                        "Use menu bar \"Clear In Call\" or wait for meeting expiration",
                        "Meeting statuses auto-expire at meeting end time (safety net)",
                        "If stuck, toggle the feature off and on in menu bar"
                    ]
                )

                troubleshootingSection(
                    icon: "pause.circle",
                    iconColor: .purple,
                    title: "How to temporarily disable features",
                    steps: [
                        "Menu bar checkmarks: toggle \"Call Detection\" or \"Calendar Sync\"",
                        "Settings persist - features stay off until re-enabled",
                        "Manual overrides (Set Active/Away) override everything"
                    ]
                )

                troubleshootingSection(
                    icon: "waveform.path",
                    iconColor: .teal,
                    title: "Status flickering between states",
                    steps: [
                        "Increase call start delay (Settings > Behavior) to 15-20 seconds",
                        "This requires sustained mic activity before triggering \"In a call\""
                    ]
                )
            }
            .padding(20)
        }
        .frame(width: 420, height: 500)
    }

    private func troubleshootingSection(
        icon: String,
        iconColor: Color,
        title: String,
        steps: [String]
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title3)
                Text(title)
                    .font(.headline)
            }

            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 8) {
                        Text("\(index + 1).")
                            .foregroundColor(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(step)
                            .font(.callout)
                    }
                }
            }
            .padding(.leading, 4)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor))
        .cornerRadius(8)
    }
}
