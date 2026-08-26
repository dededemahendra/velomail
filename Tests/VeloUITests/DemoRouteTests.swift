import Testing
import Foundation
import VeloCore
@testable import VeloUI

@MainActor
@Suite struct DemoRouteTests {
    private func app(environment: [String: String]) throws -> AppViewModel {
        let assembly = try Composition.make(
            config: AppConfig.resolve(environment: environment, configFile: nil))
        try assembly.app.start()
        return assembly.app
    }

    @Test func demoLandsOnTheListByDefault() throws {
        #expect(try app(environment: ["VELOMAIL_DEMO": "1"]).route == .list)
    }

    @Test func demoCanOpenStraightIntoASurface() throws {
        // Demo exists to be looked at; being able to look at *any* surface is
        // the difference between reviewing the UI and guessing at it.
        #expect(try app(environment: ["VELOMAIL_DEMO": "1",
                                      "VELOMAIL_DEMO_ROUTE": "compose"]).route == .compose)
        #expect(try app(environment: ["VELOMAIL_DEMO": "1",
                                      "VELOMAIL_DEMO_ROUTE": "search"]).route == .search)
        #expect(try app(environment: ["VELOMAIL_DEMO": "1",
                                      "VELOMAIL_DEMO_ROUTE": "palette"]).route == .palette)
        #expect(try app(environment: ["VELOMAIL_DEMO": "1",
                                      "VELOMAIL_DEMO_ROUTE": "thread"]).route == .thread)
    }

    @Test func anUnknownRouteIsIgnoredRatherThanFailing() throws {
        #expect(try app(environment: ["VELOMAIL_DEMO": "1",
                                      "VELOMAIL_DEMO_ROUTE": "nonsense"]).route == .list)
    }

    @Test func theRouteIsIgnoredOutsideDemo() throws {
        // A debug affordance must not be able to redirect a real launch.
        let real = try app(environment: ["VELOMAIL_CLIENT_ID": "cid",
                                         "VELOMAIL_DEMO_ROUTE": "compose"])
        #expect(real.route == .signIn)
    }
}
