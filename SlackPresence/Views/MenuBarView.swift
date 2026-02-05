import SwiftUI

struct MenuBarView: View {
    @Bindable var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Status header
            StatusIndicatorView(appState: appState)

            Divider()

            // Quick actions
            VStack(alignment: .leading, spacing: 4) {
                MenuButton(title: "Set Active", icon: "circle.fill", color: .green) {
                    Task { await ScheduleManager.shared.forceActive() }
                }

                MenuButton(title: "Set Away", icon: "moon.fill", color: .gray) {
                    Task { await ScheduleManager.shared.forceAway() }
                }

                MenuButton(title: "Resume Schedule", icon: "clock.arrow.circlepath", color: .blue) {
                    Task { await ScheduleManager.shared.resumeSchedule() }
                }
            }

            Divider()

            // Error display
            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }
        }
        .padding()
        .frame(width: 250)
    }
}

struct MenuButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                    .frame(width: 20)

                Text(title)
                    .foregroundColor(.primary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.accentColor.opacity(0.2) : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }
}

#Preview {
    MenuBarView(appState: AppState())
}
