import Foundation

final class SlackClient {
    static let shared = SlackClient()

    private let baseURL = "https://slack.com/api"
    private var credentials: SlackCredentials?

    // Retry configuration
    private let maxRetries = 3
    private let baseDelay: TimeInterval = 2.0

    private init() {
        credentials = ConfigManager.shared.loadCredentials()
    }

    // MARK: - Retry Logic

    private func performWithRetry<T>(
        operation: @escaping () async throws -> T
    ) async throws -> T {
        var lastError: Error?

        for attempt in 0..<maxRetries {
            do {
                return try await operation()
            } catch {
                lastError = error

                // Only retry transient errors
                guard isRetryable(error) else { throw error }

                // Exponential backoff: 2s, 4s, 8s
                if attempt < maxRetries - 1 {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        throw lastError ?? SlackError.invalidResponse
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let slackError = error as? SlackError {
            switch slackError {
            case .httpError(let code):
                return code >= 500 || code == 429  // Server errors, rate limit
            case .invalidResponse:
                return true  // Network issues
            default:
                return false  // Auth errors, API errors not retryable
            }
        }
        return (error as? URLError) != nil  // Network errors
    }

    func updateCredentials(_ newCredentials: SlackCredentials) {
        credentials = newCredentials
    }

    var hasValidCredentials: Bool {
        credentials?.isValid ?? false
    }

    // MARK: - Presence

    func setPresence(_ presence: SlackPresence) async throws {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        try await performWithRetry {
            guard let url = URL(string: "\(self.baseURL)/users.setPresence") else {
                throw SlackError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

            let body = "presence=\(presence.rawValue)"
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)

            try self.handleResponse(data: data, response: response)
        }
    }

    // MARK: - Status Emoji

    func setStatus(_ status: SlackStatusEmoji) async throws {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        try await performWithRetry {
            guard let url = URL(string: "\(self.baseURL)/users.profile.set") else {
                throw SlackError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

            let profile: [String: Any] = [
                "status_emoji": status.emoji,
                "status_text": status.text,
                "status_expiration": status.expiration
            ]

            let body: [String: Any] = ["profile": profile]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)

            let (data, response) = try await URLSession.shared.data(for: request)

            try self.handleResponse(data: data, response: response)
        }
    }

    func clearStatus() async throws {
        try await setStatus(.clear)
    }

    // MARK: - Do Not Disturb

    /// Pause notifications for specified minutes
    func pauseNotifications(minutes: Int) async throws {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        try await performWithRetry {
            guard let url = URL(string: "\(self.baseURL)/dnd.setSnooze") else {
                throw SlackError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

            let body = "num_minutes=\(minutes)"
            request.httpBody = body.data(using: .utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            try self.handleResponse(data: data, response: response)
        }
    }

    /// Resume notifications (end DND)
    func resumeNotifications() async throws {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        try await performWithRetry {
            guard let url = URL(string: "\(self.baseURL)/dnd.endSnooze") else {
                throw SlackError.invalidResponse
            }
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
            request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

            let (data, response) = try await URLSession.shared.data(for: request)
            try self.handleResponse(data: data, response: response)
        }
    }

    // MARK: - Fetch Presence

    /// Fetch actual presence from Slack (active/away)
    func fetchPresence() async throws -> SlackPresence {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        guard let url = URL(string: "\(baseURL)/users.getPresence") else {
            throw SlackError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SlackError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok else {
            throw SlackError.invalidResponse
        }

        let presence = json["presence"] as? String ?? "unknown"
        switch presence {
        case "active":
            return .active
        case "away":
            return .away
        default:
            return .unknown
        }
    }

    // MARK: - DND Status

    /// Fetch current DND status (snooze state)
    func fetchDNDStatus() async throws -> Bool {
        guard let creds = credentials, creds.isValid else {
            throw SlackError.noCredentials
        }

        guard let url = URL(string: "\(baseURL)/dnd.info") else {
            throw SlackError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw SlackError.invalidResponse
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool, ok else {
            throw SlackError.invalidResponse
        }

        // snooze_enabled indicates DND is actively on (user snoozed notifications)
        return json["snooze_enabled"] as? Bool ?? false
    }

    // MARK: - Response Handling

    private func handleResponse(data: Data, response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SlackError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            throw SlackError.httpError(httpResponse.statusCode)
        }

        // Parse Slack API response
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool else {
            throw SlackError.invalidResponse
        }

        if !ok {
            let error = json["error"] as? String ?? "Unknown error"
            if error == "token_revoked" || error == "invalid_auth" {
                throw SlackError.tokenExpired
            }
            throw SlackError.apiError(error)
        }
    }

    // MARK: - Test Connection

    func testConnection() async throws -> Bool {
        guard let creds = credentials, creds.isValid else {
            return false
        }

        guard let url = URL(string: "\(baseURL)/auth.test") else {
            return false
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(creds.token)", forHTTPHeaderField: "Authorization")
        request.setValue("d=\(creds.cookie)", forHTTPHeaderField: "Cookie")

        let (data, _) = try await URLSession.shared.data(for: request)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ok = json["ok"] as? Bool else {
            return false
        }

        return ok
    }
}

enum SlackError: Error, LocalizedError {
    case noCredentials
    case tokenExpired
    case invalidResponse
    case httpError(Int)
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .noCredentials:
            return "No Slack credentials configured"
        case .tokenExpired:
            return "Slack token has expired. Please update your credentials."
        case .invalidResponse:
            return "Invalid response from Slack"
        case .httpError(let code):
            return "HTTP error: \(code)"
        case .apiError(let message):
            return "Slack API error: \(message)"
        }
    }
}
