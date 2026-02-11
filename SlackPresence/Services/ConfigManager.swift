import Foundation
import Security

struct AppConfig: Codable {
    var schedules: WeekSchedule
    var callDetectionEnabled: Bool
    var pauseNotificationsWhenAway: Bool
    var scheduledStatuses: [ScheduledStatus]
    var callStartDelay: Int  // Seconds to confirm call started
    var callEndDelay: Int    // Seconds to confirm call ended
    var disabledDeviceUIDs: Set<String>  // Device UIDs user has disabled for monitoring
    var hasCompletedOnboarding: Bool
    var calendarSyncEnabled: Bool
    var selectedCalendarIDs: Set<String>
    var meetingEmoji: String
    var meetingStatusText: String
    var calendarSyncIntervalMinutes: Int
    var triggerOnBusy: Bool
    var triggerOnTentative: Bool
    var triggerOnFree: Bool
    var oooEnabled: Bool
    var oooEmoji: String
    var oooStatusText: String
    var oooPauseNotifications: Bool

    // Support old config format migration
    enum CodingKeys: String, CodingKey {
        case schedules
        case callDetectionEnabled
        case webexMonitoring  // Legacy key for migration
        case pauseNotificationsWhenAway
        case scheduledStatuses
        case callStartDelay
        case callEndDelay
        case disabledDeviceUIDs
        case hasCompletedOnboarding
        case calendarSyncEnabled
        case selectedCalendarIDs
        case meetingEmoji
        case meetingStatusText
        case calendarSyncIntervalMinutes
        case triggerOnBusy
        case triggerOnTentative
        case triggerOnFree
        case oooEnabled
        case oooEmoji
        case oooStatusText
        case oooPauseNotifications
    }

    init() {
        schedules = WeekSchedule()
        callDetectionEnabled = true
        pauseNotificationsWhenAway = false
        scheduledStatuses = []
        callStartDelay = 10
        callEndDelay = 3
        disabledDeviceUIDs = []
        hasCompletedOnboarding = false
        calendarSyncEnabled = false
        selectedCalendarIDs = []
        meetingEmoji = ":headphones:"
        meetingStatusText = "In a meeting"
        calendarSyncIntervalMinutes = 15
        triggerOnBusy = true
        triggerOnTentative = true
        triggerOnFree = false
        oooEnabled = false
        oooEmoji = ":no_entry:"
        oooStatusText = "Out of office"
        oooPauseNotifications = true
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schedules = try container.decode(WeekSchedule.self, forKey: .schedules)
        pauseNotificationsWhenAway = try container.decode(Bool.self, forKey: .pauseNotificationsWhenAway)
        scheduledStatuses = try container.decode([ScheduledStatus].self, forKey: .scheduledStatuses)
        callStartDelay = try container.decode(Int.self, forKey: .callStartDelay)
        callEndDelay = try container.decode(Int.self, forKey: .callEndDelay)
        disabledDeviceUIDs = try container.decodeIfPresent(Set<String>.self, forKey: .disabledDeviceUIDs) ?? []
        hasCompletedOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding) ?? false
        calendarSyncEnabled = try container.decodeIfPresent(Bool.self, forKey: .calendarSyncEnabled) ?? false
        selectedCalendarIDs = try container.decodeIfPresent(Set<String>.self, forKey: .selectedCalendarIDs) ?? []
        meetingEmoji = try container.decodeIfPresent(String.self, forKey: .meetingEmoji) ?? ":headphones:"
        meetingStatusText = try container.decodeIfPresent(String.self, forKey: .meetingStatusText) ?? "In a meeting"
        calendarSyncIntervalMinutes = try container.decodeIfPresent(Int.self, forKey: .calendarSyncIntervalMinutes) ?? 15
        triggerOnBusy = try container.decodeIfPresent(Bool.self, forKey: .triggerOnBusy) ?? true
        triggerOnTentative = try container.decodeIfPresent(Bool.self, forKey: .triggerOnTentative) ?? true
        triggerOnFree = try container.decodeIfPresent(Bool.self, forKey: .triggerOnFree) ?? false
        oooEnabled = try container.decodeIfPresent(Bool.self, forKey: .oooEnabled) ?? false
        oooEmoji = try container.decodeIfPresent(String.self, forKey: .oooEmoji) ?? ":palm_tree:"
        oooStatusText = try container.decodeIfPresent(String.self, forKey: .oooStatusText) ?? "Out of office"
        oooPauseNotifications = try container.decodeIfPresent(Bool.self, forKey: .oooPauseNotifications) ?? true

        // Try new key first, fall back to legacy key
        if let enabled = try? container.decode(Bool.self, forKey: .callDetectionEnabled) {
            callDetectionEnabled = enabled
        } else if let enabled = try? container.decode(Bool.self, forKey: .webexMonitoring) {
            callDetectionEnabled = enabled
        } else {
            callDetectionEnabled = true
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schedules, forKey: .schedules)
        try container.encode(callDetectionEnabled, forKey: .callDetectionEnabled)
        try container.encode(pauseNotificationsWhenAway, forKey: .pauseNotificationsWhenAway)
        try container.encode(scheduledStatuses, forKey: .scheduledStatuses)
        try container.encode(callStartDelay, forKey: .callStartDelay)
        try container.encode(callEndDelay, forKey: .callEndDelay)
        try container.encode(disabledDeviceUIDs, forKey: .disabledDeviceUIDs)
        try container.encode(hasCompletedOnboarding, forKey: .hasCompletedOnboarding)
        try container.encode(calendarSyncEnabled, forKey: .calendarSyncEnabled)
        try container.encode(selectedCalendarIDs, forKey: .selectedCalendarIDs)
        try container.encode(meetingEmoji, forKey: .meetingEmoji)
        try container.encode(meetingStatusText, forKey: .meetingStatusText)
        try container.encode(calendarSyncIntervalMinutes, forKey: .calendarSyncIntervalMinutes)
        try container.encode(triggerOnBusy, forKey: .triggerOnBusy)
        try container.encode(triggerOnTentative, forKey: .triggerOnTentative)
        try container.encode(triggerOnFree, forKey: .triggerOnFree)
        try container.encode(oooEnabled, forKey: .oooEnabled)
        try container.encode(oooEmoji, forKey: .oooEmoji)
        try container.encode(oooStatusText, forKey: .oooStatusText)
        try container.encode(oooPauseNotifications, forKey: .oooPauseNotifications)
    }
}

final class ConfigManager {
    static let shared = ConfigManager()

    private let configDirectory: URL
    private let configFile: URL

    // Keychain keys
    private let tokenKey = "com.user.slack-presence.token"
    private let cookieKey = "com.user.slack-presence.cookie"

    private init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDirectory = home.appendingPathComponent(".slackpresence")
        configFile = configDirectory.appendingPathComponent("config.json")
    }

    // MARK: - Config File

    func loadConfig() -> AppConfig {
        do {
            let data = try Data(contentsOf: configFile)
            return try JSONDecoder().decode(AppConfig.self, from: data)
        } catch {
            #if DEBUG
            print("Config load failed, using defaults: \(error)")
            #endif
            return AppConfig()
        }
    }

    func saveConfig(_ config: AppConfig) throws {
        // Ensure directory exists
        try FileManager.default.createDirectory(
            at: configDirectory,
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(config)
        try data.write(to: configFile, options: .atomic)

        // Restrict permissions: directory 0700, file 0600
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o700],
            ofItemAtPath: configDirectory.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: configFile.path
        )
    }

    // MARK: - Keychain (Credentials)

    func saveCredentials(_ credentials: SlackCredentials) throws {
        try saveToKeychain(key: tokenKey, value: credentials.token)
        try saveToKeychain(key: cookieKey, value: credentials.cookie)
    }

    func loadCredentials() -> SlackCredentials? {
        guard let token = loadFromKeychain(key: tokenKey),
              let cookie = loadFromKeychain(key: cookieKey) else {
            return nil
        }
        // Clean credentials (strip whitespace and surrounding quotes)
        let cleanedToken = cleanCredential(token)
        let cleanedCookie = cleanCredential(cookie)
        return SlackCredentials(token: cleanedToken, cookie: cleanedCookie)
    }

    /// Cleans credential value by trimming whitespace and surrounding quotes
    private func cleanCredential(_ value: String) -> String {
        var cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Remove surrounding quotes if present
        if cleaned.hasPrefix("\"") && cleaned.hasSuffix("\"") && cleaned.count > 1 {
            cleaned = String(cleaned.dropFirst().dropLast())
        }
        return cleaned
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.saveFailed(errSecParam)
        }

        // Delete existing item first
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.user.slack-presence",
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlocked
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    private func loadFromKeychain(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.user.slack-presence",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }

        return value
    }

    private func deleteFromKeychain(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.user.slack-presence",
            kSecAttrAccount as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}

enum KeychainError: Error, LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Keychain save failed with status: \(status)"
        }
    }
}
