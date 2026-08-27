import Testing
import Foundation
@testable import VeloCore

@Suite struct SendWarningTests {
    private func draft(_ body: String, subject: String = "",
                       to: [String] = ["a@x.com"],
                       attachments: [DraftAttachment] = []) -> Draft {
        Draft(to: to, subject: subject, bodyText: body, attachments: attachments)
    }

    private let file = DraftAttachment(filename: "plan.pdf", mimeType: "application/pdf",
                                       data: Data("x".utf8))

    // MARK: - The attachment nobody attached

    @Test func sayingYouAttachedSomethingWithNothingAttachedIsWorthACheck() {
        #expect(SendWarning.check(draft("See the attached plan."), recipientLimit: 0)
                == .missingAttachment)
    }

    @Test func theSameSentenceWithAFileIsFine() {
        #expect(SendWarning.check(draft("See the attached plan.", attachments: [file]),
                                  recipientLimit: 0) == nil)
    }

    @Test func theSubjectCountsToo() {
        // "Attached: invoice" with an empty body is exactly the mistake.
        #expect(SendWarning.check(draft("Thanks", subject: "Attached: invoice"),
                                  recipientLimit: 0) == .missingAttachment)
    }

    @Test func theOtherWaysPeopleSayIt() {
        for phrase in ["I've attached the map", "please find enclosed",
                       "see attachment", "attaching the signed copy",
                       "I have included the file"] {
            #expect(SendWarning.check(draft(phrase), recipientLimit: 0) == .missingAttachment,
                    "\(phrase)")
        }
    }

    @Test func aQuotedMessageMentioningOneIsNotYourClaim() {
        // Replying to "here is the attached invoice" must not nag about a file
        // the other person sent.
        let body = "Thanks, got it.\n\nOn Monday, Alice wrote:\n> See the attached invoice."
        #expect(SendWarning.check(draft(body), recipientLimit: 0) == nil)
    }

    @Test func theWordAttachedInAnotherSenseIsLeftAlone() {
        // "attached to" is about feelings or fittings, not files.
        #expect(SendWarning.check(draft("I am very attached to that garden."),
                                  recipientLimit: 0) == nil)
    }

    @Test func caseDoesNotMatter() {
        #expect(SendWarning.check(draft("ATTACHED IS THE PLAN"), recipientLimit: 0)
                == .missingAttachment)
    }

    // MARK: - Sending to a crowd

    @Test func aLargeRecipientListIsWorthAPause() {
        let many = (1...12).map { "person\($0)@x.com" }
        #expect(SendWarning.check(draft("hi", to: many), recipientLimit: 10)
                == .manyRecipients(12))
    }

    @Test func theLimitIsWhereItIsSet() {
        let ten = (1...10).map { "person\($0)@x.com" }
        #expect(SendWarning.check(draft("hi", to: ten), recipientLimit: 10) == nil)
    }

    @Test func aLimitOfZeroMeansNeverAsk() {
        let many = (1...50).map { "person\($0)@x.com" }
        #expect(SendWarning.check(draft("hi", to: many), recipientLimit: 0) == nil)
    }

    @Test func everybodyOnTheMessageCounts() {
        // Cc and Bcc are recipients; a warning that only counted To would miss
        // the send that most deserves a pause.
        let draft = Draft(to: ["a@x.com"], cc: ["b@x.com", "c@x.com"],
                          bcc: ["d@x.com"], subject: "s", bodyText: "hi")
        #expect(SendWarning.check(draft, recipientLimit: 3) == .manyRecipients(4))
    }

    // MARK: - Which one wins

    @Test func theMissingFileIsAskedAboutFirst() {
        // It is the mistake, where a crowd is usually a choice.
        let many = (1...20).map { "person\($0)@x.com" }
        #expect(SendWarning.check(draft("see attached", to: many), recipientLimit: 10)
                == .missingAttachment)
    }
}
