import Foundation

/// Runtime configuration, resolved from the environment then a config file.
///
/// A missing client id is a *state*, not an error: the app routes to a setup
/// screen that explains what to create. A mail client that dies because it has
/// no credentials is worse than one that explains itself.
public struct AppConfig: Equatable, Sendable {
    public let clientID: String?
    /// Only a Desktop-app client has one; a native client does not.
    public let clientSecret: String?
    public let isDemo: Bool
    /// Which surface a demo launch should open on, for reviewing the UI.
    /// Honoured only in demo mode -- a debug affordance must never be able to
    /// redirect a real launch.
    public let demoRoute: String?

    public var isConfigured: Bool { clientID != nil }

    /// The default location a user drops credentials into.
    public static var defaultConfigFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/velomail/config.json")
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               configFile: URL? = defaultConfigFile) -> AppConfig {
        let file = fileValues(configFile)
        return AppConfig(
            clientID: nonBlank(environment["VELOMAIL_CLIENT_ID"]) ?? nonBlank(file?.clientID),
            clientSecret: nonBlank(environment["VELOMAIL_CLIENT_SECRET"]) ?? nonBlank(file?.clientSecret),
            isDemo: nonBlank(environment["VELOMAIL_DEMO"]) != nil,
            demoRoute: nonBlank(environment["VELOMAIL_DEMO_ROUTE"])?.lowercased())
    }

    // MARK: - Internals

    /// A whitespace-only value is a half-finished setup, not a credential.
    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    private struct FileValues: Decodable {
        let clientID: String?
        let clientSecret: String?
    }

    /// A malformed or absent file resolves to "unconfigured" rather than
    /// throwing: the setup screen is a better answer than a crash on launch.
    private static func fileValues(_ url: URL?) -> FileValues? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(FileValues.self, from: data)
    }
}
