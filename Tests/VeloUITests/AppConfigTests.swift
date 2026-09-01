import Testing
import Foundation
@testable import VeloUI

@Suite struct AppConfigTests {
    private func tempConfig(_ json: String) throws -> URL {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velomail-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("config.json")
        try Data(json.utf8).write(to: file)
        return file
    }

    @Test func readsClientIDFromTheEnvironment() throws {
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "env-id"],
                                       configFile: nil)
        #expect(config.clientID == "env-id")
        #expect(config.isConfigured)
    }

    @Test func readsClientIDFromTheConfigFile() throws {
        let file = try tempConfig(#"{"clientID":"file-id"}"#)
        let config = AppConfig.resolve(environment: [:], configFile: file)
        #expect(config.clientID == "file-id")
    }

    @Test func environmentWinsOverTheConfigFile() throws {
        let file = try tempConfig(#"{"clientID":"file-id"}"#)
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "env-id"],
                                       configFile: file)
        #expect(config.clientID == "env-id")
    }

    @Test func missingCredentialsIsAStateNotAnError() {
        let config = AppConfig.resolve(environment: [:], configFile: nil)
        #expect(config.clientID == nil)
        #expect(!config.isConfigured)
        // Must still be usable enough to render a setup screen.
    }

    @Test func blankClientIDCountsAsMissing() {
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "   "], configFile: nil)
        #expect(!config.isConfigured)
    }

    @Test func aMalformedConfigFileIsTreatedAsMissingRatherThanCrashing() throws {
        let file = try tempConfig("not json at all")
        let config = AppConfig.resolve(environment: [:], configFile: file)
        #expect(!config.isConfigured)
    }

    @Test func demoModeIsOffByDefaultAndOptIn() {
        #expect(!AppConfig.resolve(environment: [:], configFile: nil).isDemo)
        #expect(AppConfig.resolve(environment: ["VELOMAIL_DEMO": "1"], configFile: nil).isDemo)
    }

    // MARK: - Client secret

    @Test func theClientSecretIsReadFromTheEnvironment() {
        let config = AppConfig.resolve(
            environment: ["VELOMAIL_CLIENT_ID": "cid", "VELOMAIL_CLIENT_SECRET": "GOCSPX-abc"],
            configFile: nil)
        #expect(config.clientSecret == "GOCSPX-abc")
    }

    @Test func theClientSecretIsReadFromTheConfigFile() throws {
        let file = try tempConfig(#"{"clientID":"cid","clientSecret":"GOCSPX-file"}"#)
        #expect(AppConfig.resolve(environment: [:], configFile: file).clientSecret == "GOCSPX-file")
    }

    @Test func aMissingSecretIsNilNotEmpty() {
        // A native client has none, and sending "" would be rejected.
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "cid"], configFile: nil)
        #expect(config.clientSecret == nil)
    }

    @Test func aBlankSecretCountsAsMissing() {
        let config = AppConfig.resolve(
            environment: ["VELOMAIL_CLIENT_ID": "cid", "VELOMAIL_CLIENT_SECRET": "  "],
            configFile: nil)
        #expect(config.clientSecret == nil)
    }

    @Test func aSecretAloneDoesNotCountAsConfigured() {
        // Without a client id there is nothing to authenticate.
        let config = AppConfig.resolve(environment: ["VELOMAIL_CLIENT_SECRET": "s"], configFile: nil)
        #expect(!config.isConfigured)
    }
}
