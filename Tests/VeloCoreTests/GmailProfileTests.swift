import Testing
import Foundation
@testable import VeloCore

@Suite struct GmailProfileTests {
    @Test func decodesEmailAndHistoryIdIgnoringCounts() throws {
        let json = Data(#"{"emailAddress":"u@x.com","historyId":"5000","messagesTotal":123,"threadsTotal":45}"#.utf8)
        let profile = try JSONDecoder().decode(GmailProfile.self, from: json)

        #expect(profile.emailAddress == "u@x.com")
        #expect(profile.historyId == "5000")
    }

    @Test func decodesWhenCountFieldsAbsent() throws {
        let json = Data(#"{"emailAddress":"u@x.com","historyId":"6000"}"#.utf8)
        let profile = try JSONDecoder().decode(GmailProfile.self, from: json)

        #expect(profile.emailAddress == "u@x.com")
        #expect(profile.historyId == "6000")
    }
}
