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
    }

    init() {
        schedules = WeekSchedule()
        callDetectionEnabled = true
        pauseNotificationsWhenAway = true
        scheduledStatuses = []
        callStartDelay = 10
        callEndDelay = 3
        disabledDeviceUIDs = []
        hasCompletedOnboarding = false
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
            print("Config load failed, using defaults: \(error)")
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
        try data.write(to: configFile)
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
        return SlackCredentials(token: token, cookie: cookie)
    }

    func deleteCredentials() {
        deleteFromKeychain(key: tokenKey)
        deleteFromKeychain(key: cookieKey)
    }

    // MARK: - Keychain Helpers

    private func saveToKeychain(key: String, value: String) throws {
        let data = value.data(using: .utf8)!

        // Delete existing item first
        deleteFromKeychain(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
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
