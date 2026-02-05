import SwiftUI

struct StatusIndicatorView: View {
    @Bindable var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            // Status icon
            ZStack {
                Circle()
                    .fill(appState.menuBarIconColor.opacity(0.2))
                    .frame(width: 40, height: 40)

                Image(systemName: appState.menuBarIcon)
                    .font(.system(size: 18))
                    .foregroundColor(appState.menuBarIconColor)
            }

            // Status text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.headline)

                Text(appState.statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)

                if appState.manualOverride != nil {
                    Text("(Manual override)")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }

            Spacer()
        }
        .padding(.horizontal)
    }

    private var statusTitle: String {
        if appState.isInCall {
            return "In Call"
        }
        return appState.effectivePresence.displayName
    }
}

// Larger status view for popover/window
struct LargeStatusView: View {
    @Bindable var appState: AppState
    @Bindable var configState: ConfigState

    var body: some View {
        VStack(spacing: 20) {
            // Large icon
            ZStack {
                Circle()
                    .fill(appState.menuBarIconColor.opacity(0.15))
                    .frame(width: 80, height: 80)

                Image(systemName: appState.menuBarIcon)
                    .font(.system(size: 36))
                    .foregroundColor(appState.menuBarIconColor)
            }

            // Status
            VStack(spacing: 4) {
                Text(statusTitle)
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(appState.statusText)
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            // Schedule info
            if let nextChange = nextScheduleChange {
                Text(nextChange)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
        .padding()
    }

    private var statusTitle: String {
        if appState.isInCall {
            return "In Call"
        }
        return appState.effectivePresence.displayName
    }

    private var nextScheduleChange: String? {
        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        let daySchedule = configState.schedule.schedule(for: weekday)

        if !daySchedule.enabled {
            return "Schedule disabled for today"
        }

        if daySchedule.isActiveAt(hour: hour, minute: minute) {
            return "Will set to Away at \(daySchedule.activeEnd)"
        } else {
            // Check if before start time
            if let start = daySchedule.startTime,
               let startHour = start.hour, let startMinute = start.minute {
                let currentMinutes = hour * 60 + minute
                let startMinutes = startHour * 60 + startMinute
                if currentMinutes < startMinutes {
                    return "Will set to Active at \(daySchedule.activeStart)"
                }
            }
            return "Next active period tomorrow"
        }
    }
}

#Preview("Small") {
    StatusIndicatorView(appState: AppState())
}

#Preview("Large") {
    LargeStatusView(appState: AppState(), configState: ConfigState())
}
