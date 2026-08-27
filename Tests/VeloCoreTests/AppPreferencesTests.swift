import Testing
import Foundation
@testable import VeloCore

@Suite struct AppPreferencesTests {
    private func makePreferences() -> (AppPreferences, UserDefaults) {
        let suite = "velo.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return (AppPreferences(defaults: defaults), defaults)
    }

    // MARK: - Sensible without being told anything

    @Test func theDefaultsAreWhatTheAppAlreadyDid() {
        // Nobody's app should change behaviour the day settings appear.
        let (preferences, _) = makePreferences()
        #expect(preferences.undoWindow == 10)
        #expect(preferences.snoozeHours == 4)
        #expect(preferences.morningHour == 9)
        #expect(preferences.syncInterval == 60)
        #expect(preferences.loadsRemoteImages)
        #expect(preferences.showsNotifications)
    }

    @Test func theExistingImageChoiceIsNotLost() {
        // It shipped under its own key before there was anywhere else to put
        // it, and someone who turned blocking on meant it.
        let (preferences, defaults) = makePreferences()
        defaults.set(true, forKey: "velomail.blockRemoteImages")

        #expect(!preferences.loadsRemoteImages)
    }

    // MARK: - Remembering

    @Test func achoiceSurvivesRelaunching() {
        let (preferences, defaults) = makePreferences()
        preferences.undoWindow = 30

        #expect(AppPreferences(defaults: defaults).undoWindow == 30)
    }

    @Test func everySettingRoundTrips() {
        let (preferences, defaults) = makePreferences()
        preferences.undoWindow = 25
        preferences.snoozeHours = 2
        preferences.morningHour = 6
        preferences.syncInterval = 300
        preferences.loadsRemoteImages = false
        preferences.showsNotifications = false

        let reloaded = AppPreferences(defaults: defaults)
        #expect(reloaded.undoWindow == 25)
        #expect(reloaded.snoozeHours == 2)
        #expect(reloaded.morningHour == 6)
        #expect(reloaded.syncInterval == 300)
        #expect(!reloaded.loadsRemoteImages)
        #expect(!reloaded.showsNotifications)
    }

    // MARK: - Refusing to be set to something harmful

    @Test func theUndoWindowCannotBeSetToNothing() {
        // Zero means a send that cannot be taken back, which is the one thing
        // the window exists for.
        let (preferences, _) = makePreferences()
        preferences.undoWindow = 0

        #expect(preferences.undoWindow >= 3)
    }

    @Test func theUndoWindowCannotBeSetToForever() {
        // Mail that sits unsent for an hour is mail the writer thinks was sent.
        let (preferences, _) = makePreferences()
        preferences.undoWindow = 9_999

        #expect(preferences.undoWindow <= 60)
    }

    @Test func syncCannotBeSetToHammerGmail() {
        let (preferences, _) = makePreferences()
        preferences.syncInterval = 1

        #expect(preferences.syncInterval >= 15)
    }

    @Test func theMorningHourStaysWithinADay() {
        let (preferences, _) = makePreferences()
        preferences.morningHour = 47

        #expect((0...23).contains(preferences.morningHour))
    }

    @Test func aSnoozeIsAtLeastLongEnoughToBeWorthIt() {
        let (preferences, _) = makePreferences()
        preferences.snoozeHours = 0

        #expect(preferences.snoozeHours >= 1)
    }

    // MARK: - Composing

    @Test func replyingToEveryoneIsOffByDefault() {
        // Answering more people than intended is the harder mistake to take
        // back, and Shift+R is right there.
        let (preferences, _) = makePreferences()
        #expect(!preferences.repliesToEveryone)
    }

    @Test func quotingAndTheAttachmentCheckAreOnByDefault() {
        let (preferences, _) = makePreferences()
        #expect(preferences.quotesByDefault)
        #expect(preferences.warnsAboutAttachments)
    }

    @Test func askingAboutACrowdIsOffUntilANumberIsGiven() {
        // A client that questions every send teaches people to dismiss it
        // without reading.
        let (preferences, _) = makePreferences()
        #expect(preferences.recipientLimit == 0)
    }

    @Test func theRecipientLimitCannotBeNegative() {
        let (preferences, _) = makePreferences()
        preferences.recipientLimit = -5
        #expect(preferences.recipientLimit == 0)
    }

    // MARK: - Reading

    @Test func markingReadIsImmediateByDefault() {
        let (preferences, _) = makePreferences()
        #expect(preferences.marksReadAfter == 0)
    }

    @Test func neverMarkingReadIsAllowed() {
        // Someone triaging a busy inbox wants to open things without losing
        // track of what they have not dealt with.
        let (preferences, _) = makePreferences()
        preferences.marksReadAfter = -1
        #expect(preferences.marksReadAfter == -1)
    }

    @Test func aDelayIsCappedAtSomethingSensible() {
        let (preferences, _) = makePreferences()
        preferences.marksReadAfter = 600
        #expect(preferences.marksReadAfter == 30)
    }

    @Test func theAppOpensOnTheInboxUnlessToldOtherwise() {
        let (preferences, _) = makePreferences()
        #expect(preferences.opensAt == "inbox")
    }
}
