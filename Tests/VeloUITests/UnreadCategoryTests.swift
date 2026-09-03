import Testing
import Foundation
import VeloCore
@testable import VeloUI

private struct Quiet: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {}
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO { fatalError() }
}

/// On a real mailbox the badge sat at 114 while Gmail showed 1. Neither was
/// miscounting: 84 of those were Updates, 17 Promotions, 12 Social, and Gmail's
/// own count ignores all three.
///
/// A badge that never goes down is the red light nobody looks at, so Primary is
/// the default -- but which mail counts as waiting is the reader's business,
/// and the setting is there.
@MainActor
@Suite struct UnreadCategoryTests {
    private func store(with categories: [String?]) throws -> MailStore {
        let store = MailStore(try AppDatabase.makeInMemory())
        for (index, category) in categories.enumerated() {
            let labels = ["INBOX"] + (category.map { [$0] } ?? [])
            try store.upsert(MailThread(id: "t\(index)", sender: "a@b.com", snippet: "s",
                                        lastMessageDate: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                                        isUnread: true, hasAttachments: false, labelIDs: labels))
        }
        return store
    }

    /// The shape of the mailbox that prompted this.
    private let realWorld: [String?] = ["CATEGORY_PERSONAL"]
        + Array(repeating: "CATEGORY_UPDATES", count: 84)
        + Array(repeating: "CATEGORY_PROMOTIONS", count: 17)
        + Array(repeating: "CATEGORY_SOCIAL", count: 12)

    @Test func primaryIsTheDefaultAndMatchesWhatGmailShows() throws {
        #expect(try store(with: realWorld).unreadInboxCount(includingEveryCategory: false) == 1)
    }

    @Test func countingEverythingIsStillAvailableAndCountsEverything() throws {
        #expect(try store(with: realWorld).unreadInboxCount(includingEveryCategory: true) == 114)
    }

    /// Gmail leaves plenty of Primary mail with no category label at all, so
    /// Primary has to be "not one of the other four" rather than "tagged
    /// PERSONAL" -- the other spelling would count almost nothing.
    @Test func mailWithNoCategoryAtAllCountsAsPrimary() throws {
        let mixed = try store(with: [nil, nil, "CATEGORY_PERSONAL", "CATEGORY_PROMOTIONS"])
        #expect(try mixed.unreadInboxCount(includingEveryCategory: false) == 3)
    }

    @Test func theSettingIsWhatDecidesIt() throws {
        let store = try store(with: realWorld)
        let preferences = AppPreferences(defaults: scratchDefaults())
        let app = AppViewModel(
            config: AppConfig.resolve(environment: ["VELOMAIL_CLIENT_ID": "c"], configFile: nil),
            store: store,
            outbound: OutboundService(writer: Quiet(), store: store,
                                      mutations: MutationStore(try AppDatabase.makeInMemory()),
                                      identity: "me@x.com"),
            identity: "me@x.com", isSignedIn: true, preferences: preferences)
        try app.start()

        #expect(app.visibleUnreadCount == 1)

        preferences.countsEveryCategory = true
        #expect(app.visibleUnreadCount == 114)
    }
}
