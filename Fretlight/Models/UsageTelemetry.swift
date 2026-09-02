import CryptoKit
import Foundation

/// The smallest useful telemetry Fretwork can collect: one opt-in pulse per
/// local UTC day. The app never sends a microphone sample, detected note,
/// chord history, device identifier, or a durable installation identifier.
///
/// The three tokens are derived locally from a random installation secret and
/// rotate at different calendar boundaries. They let the aggregate report show
/// daily, weekly, and monthly active installations without creating an ID that
/// follows a player indefinitely.
@MainActor
final class UsageTelemetry {
    static let endpoint = URL(string: "https://telemetry.fretwork.org/v1/active")!

    private static let installationSecretKey = "fretwork.usage-telemetry-installation-secret"
    private static let lastSubmittedDayKey = "fretwork.usage-telemetry-last-submitted-day"

    private let defaults: UserDefaults
    private var inFlightDay: String?

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Fire-and-forget by design. Analytics must never delay the window, audio
    /// graph, or a normal user action, and a failed request simply tries again
    /// on a later launch.
    func recordActiveDayIfEnabled(_ isEnabled: Bool) {
        guard isEnabled, !Self.isRunningTests else { return }

        let now = Date()
        let tokens = Self.tokens(for: now, installationSecret: installationSecret())
        guard defaults.string(forKey: Self.lastSubmittedDayKey) != tokens.day,
              inFlightDay != tokens.day else { return }
        inFlightDay = tokens.day

        let payload = Payload(
            schema: 1,
            dayToken: tokens.dayToken,
            weekToken: tokens.weekToken,
            monthToken: tokens.monthToken,
            version: Self.appVersion
        )
        Task { [weak self] in
            guard let self else { return }
            let sent = await self.send(payload)
            if sent { self.defaults.set(tokens.day, forKey: Self.lastSubmittedDayKey) }
            self.inFlightDay = nil
        }
    }

    private func installationSecret() -> String {
        if let value = defaults.string(forKey: Self.installationSecretKey), !value.isEmpty {
            return value
        }
        let value = UUID().uuidString
        defaults.set(value, forKey: Self.installationSecretKey)
        return value
    }

    private func send(_ payload: Payload) async -> Bool {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 3
        request.httpBody = try? JSONEncoder().encode(payload)
        guard request.httpBody != nil else { return false }

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 204
        } catch {
            return false
        }
    }

    private static var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
        return "\(version) (\(build))"
    }

    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    struct Tokens: Equatable {
        let day: String
        let dayToken: String
        let weekToken: String
        let monthToken: String
    }

    nonisolated static func tokens(for date: Date, installationSecret: String) -> Tokens {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!

        let day = calendar.dateComponents([.year, .month, .day], from: date)
        let dayLabel = String(format: "%04d-%02d-%02d", day.year!, day.month!, day.day!)
        let weekLabel = String(
            format: "%04d-W%02d",
            calendar.component(.yearForWeekOfYear, from: date),
            calendar.component(.weekOfYear, from: date)
        )
        let monthLabel = String(format: "%04d-%02d", day.year!, day.month!)
        return Tokens(
            day: dayLabel,
            dayToken: token(secret: installationSecret, period: "day", label: dayLabel),
            weekToken: token(secret: installationSecret, period: "week", label: weekLabel),
            monthToken: token(secret: installationSecret, period: "month", label: monthLabel)
        )
    }

    nonisolated private static func token(secret: String, period: String, label: String) -> String {
        let input = Data("\(secret)|\(period)|\(label)".utf8)
        return SHA256.hash(data: input).map { String(format: "%02x", $0) }.joined()
    }

    private struct Payload: Encodable {
        let schema: Int
        let dayToken: String
        let weekToken: String
        let monthToken: String
        let version: String
    }
}
