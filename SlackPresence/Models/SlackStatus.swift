import Foundation

enum SlackPresence: String, Codable {
    case active = "auto"
    case away = "away"
    case unknown

    var displayName: String {
        switch self {
        case .active: return "Active"
        case .away: return "Away"
        case .unknown: return "Unknown"
        }
    }
}

struct SlackStatusEmoji: Equatable {
    let emoji: String
    let text: String
    let expiration: Int  // Unix timestamp, 0 = no expiration

    static let inMeeting = SlackStatusEmoji(
        emoji: ":headphones:",
        text: "In a call",
        expiration: 0
    )

    static let clear = SlackStatusEmoji(
        emoji: "",
        text: "",
        expiration: 0
    )

    static func meeting(emoji: String, text: String, endDate: Date) -> SlackStatusEmoji {
        SlackStatusEmoji(
            emoji: emoji,
            text: text,
            expiration: Int(endDate.timeIntervalSince1970)
        )
    }

    static func outOfOffice(emoji: String, text: String, endDate: Date) -> SlackStatusEmoji {
        SlackStatusEmoji(
            emoji: emoji,
            text: text,
            expiration: Int(endDate.timeIntervalSince1970)
        )
    }
}

struct SlackCredentials: Codable {
    let token: String      // xoxc-... token
    let cookie: String     // d cookie value

    var isValid: Bool {
        token.hasPrefix("xoxc-") && !cookie.isEmpty
    }
}
