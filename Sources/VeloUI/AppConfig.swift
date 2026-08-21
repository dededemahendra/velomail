import Foundation

/// Runtime configuration, resolved from the environment then a config file.
///
/// A missing client id is a *state*, not an error: the app routes to a setup
/// screen that explains what to create. A mail client that dies because it has
/// no credentials is worse than one that explains itself.
public struct AppConfig: Equatable, Sendable {
    public let clientID: String?
    public let isDemo: Bool

    public var isConfigured: Bool { clientID != nil }

    /// The default location a user drops credentials into.
    public static var defaultConfigFile: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".config/velomail/config.json")
    }

    public static func resolve(environment: [String: String] = ProcessInfo.processInfo.environment,
                               configFile: URL? = defaultConfigFile) -> AppConfig {
        AppConfig(clientID: nonBlank(environment["VELOMAIL_CLIENT_ID"]) ?? clientIDFromFile(configFile),
                  isDemo: nonBlank(environment["VELOMAIL_DEMO"]) != nil)
    }

    public static let setupInstructions = """
        Velo Mail needs a Google Cloud OAuth client id (Desktop app type) with \
        the Gmail API enabled.

        Create one at console.cloud.google.com → APIs & Services → Credentials, \
        then provide it either way:

          • export VELOMAIL_CLIENT_ID="…apps.googleusercontent.com"
          • or ~/.config/velomail/config.json  →  {"clientID": "…"}

        Restart Velo Mail once it is set.

        To look around without an account first, launch with VELOMAIL_DEMO=1.
        """

    // MARK: - Internals

    /// A whitespace-only value is a half-finished setup, not a credential.
    private static func nonBlank(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// A malformed or absent file resolves to "unconfigured" rather than
    /// throwing: the setup screen is a better answer than a crash on launch.
    private static func clientIDFromFile(_ url: URL?) -> String? {
        guard let url, let data = try? Data(contentsOf: url) else { return nil }
        struct File: Decodable { let clientID: String? }
        return nonBlank(try? JSONDecoder().decode(File.self, from: data).clientID)
    }
}
