import Foundation

// MARK: - Scheduled Status

struct ScheduledStatus: Codable, Equatable, Identifiable {
    var id: UUID
    var emoji: String           // e.g., ":pizza:", ":coffee:"
    var text: String            // e.g., "Lunch break"
    var startTime: String       // "HH:mm" format
    var endTime: String         // "HH:mm" format
    var daysOfWeek: [Int]       // Calendar weekdays: 1=Sun, 2=Mon, etc.
    var enabled: Bool

    init(
        id: UUID = UUID(),
        emoji: String = ":coffee:",
        text: String = "Taking a break",
        startTime: String = "12:00",
        endTime: String = "13:00",
        daysOfWeek: [Int] = [1, 2, 3, 4, 5],  // Sun-Thu (Israel)
        enabled: Bool = true
    ) {
        self.id = id
        self.emoji = emoji
        self.text = text
        self.startTime = startTime
        self.endTime = endTime
        self.daysOfWeek = daysOfWeek
        self.enabled = enabled
    }

    func isActiveNow() -> Bool {
        guard enabled else { return false }

        let now = Date()
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: now)
        let hour = calendar.component(.hour, from: now)
        let minute = calendar.component(.minute, from: now)

        // Check if today is in the scheduled days
        guard daysOfWeek.contains(weekday) else { return false }

        // Parse times
        let startParts = startTime.split(separator: ":")
        let endParts = endTime.split(separator: ":")

        guard startParts.count == 2, endParts.count == 2,
              let startHour = Int(startParts[0]), let startMin = Int(startParts[1]),
              let endHour = Int(endParts[0]), let endMin = Int(endParts[1]) else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMin
        let endMinutes = endHour * 60 + endMin

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
}

// MARK: - Day Schedule

struct DaySchedule: Codable, Equatable {
    var activeStart: String  // "HH:mm" format
    var activeEnd: String    // "HH:mm" format
    var enabled: Bool

    init(activeStart: String = "08:00", activeEnd: String = "19:00", enabled: Bool = true) {
        self.activeStart = activeStart
        self.activeEnd = activeEnd
        self.enabled = enabled
    }

    var startTime: DateComponents? {
        parseTime(activeStart)
    }

    var endTime: DateComponents? {
        parseTime(activeEnd)
    }

    private func parseTime(_ timeString: String) -> DateComponents? {
        let parts = timeString.split(separator: ":")
        guard parts.count == 2,
              let hour = Int(parts[0]),
              let minute = Int(parts[1]) else {
            return nil
        }
        return DateComponents(hour: hour, minute: minute)
    }

    func isActiveAt(hour: Int, minute: Int) -> Bool {
        guard enabled,
              let start = startTime,
              let end = endTime,
              let startHour = start.hour, let startMinute = start.minute,
              let endHour = end.hour, let endMinute = end.minute else {
            return false
        }

        let currentMinutes = hour * 60 + minute
        let startMinutes = startHour * 60 + startMinute
        let endMinutes = endHour * 60 + endMinute

        return currentMinutes >= startMinutes && currentMinutes < endMinutes
    }
}

struct WeekSchedule: Codable, Equatable {
    var monday: DaySchedule
    var tuesday: DaySchedule
    var wednesday: DaySchedule
    var thursday: DaySchedule
    var friday: DaySchedule
    var saturday: DaySchedule
    var sunday: DaySchedule

    init() {
        // Default: All days disabled for new users
        sunday = DaySchedule(enabled: false)
        monday = DaySchedule(enabled: false)
        tuesday = DaySchedule(enabled: false)
        wednesday = DaySchedule(enabled: false)
        thursday = DaySchedule(enabled: false)
        friday = DaySchedule(enabled: false)
        saturday = DaySchedule(enabled: false)
    }

    func schedule(for weekday: Int) -> DaySchedule {
        // Calendar weekday: 1 = Sunday, 2 = Monday, etc.
        switch weekday {
        case 1: return sunday
        case 2: return monday
        case 3: return tuesday
        case 4: return wednesday
        case 5: return thursday
        case 6: return friday
        case 7: return saturday
        default: return monday
        }
    }

    mutating func setSchedule(_ schedule: DaySchedule, for weekday: Int) {
        switch weekday {
        case 1: sunday = schedule
        case 2: monday = schedule
        case 3: tuesday = schedule
        case 4: wednesday = schedule
        case 5: thursday = schedule
        case 6: friday = schedule
        case 7: saturday = schedule
        default: break
        }
    }
}
