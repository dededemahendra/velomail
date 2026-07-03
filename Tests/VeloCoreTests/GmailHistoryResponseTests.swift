import Testing
import Foundation
@testable import VeloCore

private func decodeHistory(_ json: String) throws -> GmailHistoryResponse {
    try JSONDecoder().decode(GmailHistoryResponse.self, from: Data(json.utf8))
}

@Suite struct GmailHistoryResponseTests {
    @Test func collectsAddedMessageIDsAcrossRecords() throws {
        let json = """
        {
          "history": [
            {"id": "1", "messagesAdded": [{"message": {"id": "m1", "threadId": "t1"}}]},
            {"id": "2", "messagesAdded": [
              {"message": {"id": "m2", "threadId": "t2"}},
              {"message": {"id": "m3", "threadId": "t2"}}
            ]}
          ],
          "historyId": "2050",
          "nextPageToken": "page-2"
        }
        """
        let response = try decodeHistory(json)

        #expect(response.addedMessageIDs == ["m1", "m2", "m3"])
        #expect(response.historyId == "2050")
        #expect(response.nextPageToken == "page-2")
    }

    @Test func absentHistoryYieldsNoAddedIDs() throws {
        let response = try decodeHistory(#"{"historyId": "3000"}"#)

        #expect(response.addedMessageIDs == [])
        #expect(response.nextPageToken == nil)
        #expect(response.historyId == "3000")
    }

    @Test func recordWithoutMessagesAddedContributesNothing() throws {
        let json = """
        {"history": [{"id": "9", "labelsRemoved": [{"message": {"id": "x"}}]}], "historyId": "1"}
        """
        let response = try decodeHistory(json)

        #expect(response.addedMessageIDs == [])
    }
}
