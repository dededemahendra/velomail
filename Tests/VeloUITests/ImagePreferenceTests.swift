import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ImagePreferenceTests {
    private func makeDefaults() -> UserDefaults {
        let suite = "velo.test.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @Test func imagesLoadByDefault() {
        // Blocking is the more private choice, and it was the default until a
        // real mailbox showed what it costs: most messages arriving with holes
        // in them, which reads as a broken client rather than a careful one.
        // Blocking stays one command away.
        #expect(ImagePreference(defaults: makeDefaults()).alwaysLoads)
    }

    @Test func blockingCanBeTurnedOn() {
        let defaults = makeDefaults()
        ImagePreference(defaults: defaults).alwaysLoads = false

        #expect(!ImagePreference(defaults: defaults).alwaysLoads)
    }

    @Test func theChoiceIsRemembered() {
        // The point of the setting is not having to answer every message.
        let defaults = makeDefaults()
        ImagePreference(defaults: defaults).alwaysLoads = false

        #expect(!ImagePreference(defaults: defaults).alwaysLoads)
    }

    @Test func togglingReportsWhatItBecame() {
        let preference = ImagePreference(defaults: makeDefaults())
        #expect(preference.toggle() == false)
        #expect(preference.toggle() == true)
    }
}
