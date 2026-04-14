import SwiftUI

struct StatusScheduleEditorView: View {
    @Bindable var configState: ConfigState
    @State private var selectedStatus: ScheduledStatus?
    @State private var showingAddSheet = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Scheduled Statuses")
                    .font(.headline)
                Spacer()
                Button(action: { showingAddSheet = true }) {
                    Image(systemName: "plus")
                }
            }
            .padding()

            Divider()

            if configState.scheduledStatuses.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.system(size: 40))
                        .foregroundColor(.secondary)
                    Text("No scheduled statuses")
                        .foregroundColor(.secondary)
                    Text("Add a status to automatically update your Slack status at specific times.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(configState.scheduledStatuses) { status in
                        StatusRowView(status: status, onEdit: {
                            selectedStatus = status
                        }, onToggle: { enabled in
                            var updated = status
                            updated.enabled = enabled
                            ScheduleManager.shared.updateScheduledStatus(updated)
                            ScheduleManager.shared.saveConfig()
                        })
                    }
                    .onDelete(perform: deleteStatuses)
                }
            }

            Divider()

            // Footer
            HStack {
                Text("Statuses are applied automatically during their scheduled times.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Save") {
                    ScheduleManager.shared.saveConfig()
                }
            }
            .padding()
        }
        .frame(minWidth: 500, minHeight: 400)
        .sheet(isPresented: $showingAddSheet) {
            StatusEditSheet(status: nil) { newStatus in
                ScheduleManager.shared.addScheduledStatus(newStatus)
                ScheduleManager.shared.saveConfig()
            }
        }
        .sheet(item: $selectedStatus) { status in
            StatusEditSheet(status: status) { updatedStatus in
                ScheduleManager.shared.updateScheduledStatus(updatedStatus)
                ScheduleManager.shared.saveConfig()
            }
        }
    }

    private func deleteStatuses(at offsets: IndexSet) {
        for index in offsets {
            let status = configState.scheduledStatuses[index]
            ScheduleManager.shared.removeScheduledStatus(status)
        }
        ScheduleManager.shared.saveConfig()
    }
}

struct StatusRowView: View {
    let status: ScheduledStatus
    let onEdit: () -> Void
    let onToggle: (Bool) -> Void

    var body: some View {
        HStack {
            Toggle("", isOn: Binding(
                get: { status.enabled },
                set: { onToggle($0) }
            ))
            .labelsHidden()

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(status.emoji)
                    Text(status.text)
                        .fontWeight(.medium)
                }

                Text("\(status.startTime) - \(status.endTime) • \(daysDescription)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .opacity(status.enabled ? 1.0 : 0.5)
    }

    private var daysDescription: String {
        let dayNames = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
        let days = status.daysOfWeek.sorted().compactMap { weekday -> String? in
            guard weekday >= 1, weekday <= 7 else { return nil }
            return dayNames[weekday - 1]
        }

        if days.count == 7 {
            return "Every day"
        } else if days == ["Mon", "Tue", "Wed", "Thu", "Fri"] {
            return "Weekdays"
        } else if days == ["Sat", "Sun"] {
            return "Weekends"
        } else {
            return days.joined(separator: ", ")
        }
    }
}

struct StatusEditSheet: View {
    let status: ScheduledStatus?
    let onSave: (ScheduledStatus) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var emoji: String = ":coffee:"
    @State private var text: String = "Taking a break"
    @State private var startTime: String = "12:00"
    @State private var endTime: String = "13:00"
    @State private var selectedDays: Set<Int> = [1, 2, 3, 4, 5]  // Sun-Thu (Israel)
    @State private var enabled: Bool = true

    private let weekdays = [
        (1, "Sun"), (2, "Mon"), (3, "Tue"), (4, "Wed"),
        (5, "Thu"), (6, "Fri"), (7, "Sat")
    ]

    private let commonEmojis = [
        ":coffee:", ":pizza:", ":house:", ":palm_tree:",
        ":books:", ":computer:", ":phone:", ":zzz:",
        ":runner:", ":car:", ":airplane:", ":headphones:"
    ]

    var body: some View {
        VStack(spacing: 20) {
            Text(status == nil ? "Add Scheduled Status" : "Edit Scheduled Status")
                .font(.headline)

            // Emoji picker
            VStack(alignment: .leading, spacing: 8) {
                Text("Emoji:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    ForEach(commonEmojis, id: \.self) { e in
                        Button(action: { emoji = e }) {
                            Text(emojiFromCode(e))
                                .font(.title2)
                                .padding(4)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(emoji == e ? Color.accentColor.opacity(0.3) : Color.clear)
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                TextField("Or enter emoji code", text: $emoji)
                    .textFieldStyle(.roundedBorder)
            }

            // Status text
            VStack(alignment: .leading, spacing: 4) {
                Text("Status text:")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextField("Status text", text: $text)
                    .textFieldStyle(.roundedBorder)
            }

            // Time range
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Start time:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TimePickerField(time: $startTime)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("End time:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    TimePickerField(time: $endTime)
                }
            }

            // Days of week
            VStack(alignment: .leading, spacing: 8) {
                Text("Days:")
                    .font(.caption)
                    .foregroundColor(.secondary)

                HStack(spacing: 4) {
                    ForEach(weekdays, id: \.0) { day in
                        DayToggleButton(
                            title: day.1,
                            isSelected: selectedDays.contains(day.0)
                        ) {
                            if selectedDays.contains(day.0) {
                                selectedDays.remove(day.0)
                            } else {
                                selectedDays.insert(day.0)
                            }
                        }
                    }
                }

                HStack {
                    Button("Weekdays") {
                        selectedDays = [1, 2, 3, 4, 5]  // Sun-Thu (Israel)
                    }
                    Button("Weekends") {
                        selectedDays = [6, 7]  // Fri-Sat (Israel)
                    }
                    Button("Every day") {
                        selectedDays = [1, 2, 3, 4, 5, 6, 7]
                    }
                }
                .font(.caption)
            }

            Spacer()

            // Buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    let newStatus = ScheduledStatus(
                        id: status?.id ?? UUID(),
                        emoji: emoji,
                        text: text,
                        startTime: startTime,
                        endTime: endTime,
                        daysOfWeek: Array(selectedDays),
                        enabled: enabled
                    )
                    onSave(newStatus)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.isEmpty || selectedDays.isEmpty)
            }
        }
        .padding()
        .frame(width: 450, height: 420)
        .onAppear {
            if let status = status {
                emoji = status.emoji
                text = status.text
                startTime = status.startTime
                endTime = status.endTime
                selectedDays = Set(status.daysOfWeek)
                enabled = status.enabled
            }
        }
    }

    private func emojiFromCode(_ code: String) -> String {
        // Convert Slack emoji codes to actual emojis for display
        let emojiMap: [String: String] = [
            ":coffee:": "☕️", ":pizza:": "🍕", ":house:": "🏠", ":palm_tree:": "🌴",
            ":books:": "📚", ":computer:": "💻", ":phone:": "📱", ":zzz:": "💤",
            ":runner:": "🏃", ":car:": "🚗", ":airplane:": "✈️", ":headphones:": "🎧"
        ]
        return emojiMap[code] ?? code
    }
}

struct DayToggleButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(isSelected ? Color.accentColor : Color.gray.opacity(0.2))
                )
                .foregroundColor(isSelected ? .white : .primary)
        }
        .buttonStyle(.plain)
    }
}

struct TimePickerField: View {
    @Binding var time: String

    @State private var hour: Int = 12
    @State private var minute: Int = 0

    var body: some View {
        HStack(spacing: 4) {
            Picker("", selection: $hour) {
                ForEach(0..<24, id: \.self) { h in
                    Text(String(format: "%02d", h)).tag(h)
                }
            }
            .labelsHidden()
            .frame(width: 60)

            Text(":")

            Picker("", selection: $minute) {
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
            hour = Int(parts[0]) ?? 12
            minute = Int(parts[1]) ?? 0
        }
    }

    private func updateTime() {
        time = String(format: "%02d:%02d", hour, minute)
    }
}

#Preview {
    StatusScheduleEditorView(configState: ConfigState())
}
