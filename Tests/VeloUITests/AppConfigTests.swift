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
        #expect(!AppConfig.setupInstructions.isEmpty)
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
}
