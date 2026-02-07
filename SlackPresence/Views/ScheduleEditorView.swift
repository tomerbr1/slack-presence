import SwiftUI

struct ScheduleEditorView: View {
    @Bindable var configState: ConfigState

    @State private var selectedDay: Int = 1  // Sunday (Israel workweek)
    @State private var originalSchedule: WeekSchedule?
    @State private var showDiscardAlert = false

    private var hasUnsavedChanges: Bool {
        guard let original = originalSchedule else { return false }
        return configState.schedule != original
    }

    private let weekdays = [
        (1, "Sunday"),
        (2, "Monday"),
        (3, "Tuesday"),
        (4, "Wednesday"),
        (5, "Thursday"),
        (6, "Friday"),
        (7, "Saturday")
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Day selector
            HStack(spacing: 4) {
                ForEach(weekdays, id: \.0) { day in
                    DayButton(
                        title: String(day.1.prefix(3)),
                        isSelected: selectedDay == day.0,
                        isEnabled: configState.schedule.schedule(for: day.0).enabled
                    ) {
                        selectedDay = day.0
                    }
                }
            }
            .padding()

            Divider()

            // Selected day editor
            DayScheduleEditor(
                dayName: weekdays.first { $0.0 == selectedDay }?.1 ?? "Day",
                schedule: binding(for: selectedDay)
            )
            .padding()

            Divider()

            // Quick actions
            HStack {
                Button("Copy to Weekdays") {
                    copyToWeekdays()
                }

                Button("Copy to All Days") {
                    copyToAll()
                }

                Spacer()

                Button("Cancel") {
                    if hasUnsavedChanges {
                        showDiscardAlert = true
                    } else {
                        closeWindow()
                    }
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    save()
                    closeWindow()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()

            // Config file location hint
            HStack {
                Image(systemName: "folder")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Text("Config stored at ~/.slackpresence/config.json")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
        .frame(minWidth: 450, minHeight: 400)
        .onAppear {
            originalSchedule = configState.schedule
        }
        .alert("Discard Changes?", isPresented: $showDiscardAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                // Restore original schedule
                if let original = originalSchedule {
                    configState.schedule = original
                }
                closeWindow()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }
    }

    private func closeWindow() {
        NSApp.keyWindow?.close()
    }

    private func binding(for weekday: Int) -> Binding<DaySchedule> {
        Binding(
            get: { configState.schedule.schedule(for: weekday) },
            set: { configState.schedule.setSchedule($0, for: weekday) }
        )
    }

    private func copyToWeekdays() {
        let source = configState.schedule.schedule(for: selectedDay)
        for day in 1...5 {  // Sun-Thu (Israel workweek)
            configState.schedule.setSchedule(source, for: day)
        }
    }

    private func copyToAll() {
        let source = configState.schedule.schedule(for: selectedDay)
        for day in 1...7 {
            configState.schedule.setSchedule(source, for: day)
        }
    }

    private func save() {
        ScheduleManager.shared.saveConfig()
    }
}

struct DayButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .white : (isEnabled ? .primary : .secondary))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? Color.accentColor : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isEnabled ? Color.accentColor.opacity(0.5) : Color.gray.opacity(0.3), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct DayScheduleEditor: View {
    let dayName: String
    @Binding var schedule: DaySchedule

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Toggle(isOn: $schedule.enabled) {
                Text(dayName)
                    .font(.headline)
            }
            .toggleStyle(.switch)

            if schedule.enabled {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text("Active from:")
                            .frame(width: 100, alignment: .leading)

                        TimeField(time: $schedule.activeStart)
                    }

                    HStack {
                        Text("Active until:")
                            .frame(width: 100, alignment: .leading)

                        TimeField(time: $schedule.activeEnd)
                    }
                }
                .padding(.leading, 20)

                // Preview
                Text("You will be set to **Active** from \(schedule.activeStart) to \(schedule.activeEnd)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            } else {
                Text("Slack presence will **not be managed** on this day")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
    }
}

struct TimeField: View {
    @Binding var time: String

    @State private var hour: Int = 9
    @State private var minute: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Picker("Hour", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 60)

            Text(":")

            Picker("Minute", selection: $minute) {
                ForEach([0, 15, 30, 45], id: \.self) { m in
                    Text(String(format: "%02d", m)).tag(m)
                }
            }
            .labelsHidden()
            .frame(width: 60)
        }
        .onAppear {
            parseTime()
        }
        .onChange(of: hour) { _, _ in updateTime() }
        .onChange(of: minute) { _, _ in updateTime() }
    }

    private func parseTime() {
        let parts = time.split(separator: ":")
        if parts.count == 2 {
            hour = Int(parts[0]) ?? 9
            minute = Int(parts[1]) ?? 0
        }
    }

    private func updateTime() {
        time = String(format: "%02d:%02d", hour, minute)
    }
}

#Preview {
    ScheduleEditorView(configState: ConfigState())
}
