import Testing
import Foundation
@testable import VeloCore

@Suite struct SendWarningTests {
    // A subject by default: these cases are about attachments and recipient
    // counts, and an empty one is now a warning in its own right.
    private func draft(_ body: String, subject: String = "Hello",
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

    // MARK: - An address that cannot be delivered to

    @Test func anAddressWithNoAtSignIsCaughtBeforeItIsSent() {
        // Gmail refuses it, but the refusal arrives long after the window has
        // closed and the undo window has run out, as a line in the failure
        // queue.
        #expect(SendWarning.check(draft("hi", to: ["petaexample.com"]), recipientLimit: 0)
                == .malformedAddress("petaexample.com"))
    }

    @Test func aDomainWithNoDotIsCaughtToo() {
        #expect(SendWarning.check(draft("hi", to: ["peta@localhost"]), recipientLimit: 0)
                == .malformedAddress("peta@localhost"))
    }

    @Test func theBadOneIsNamedSoItCanBeFound() {
        // Three recipients and one typo: saying which is the whole value.
        let warning = SendWarning.check(draft("hi", to: ["a@x.com", "b@@x.com", "c@x.com"]),
                                        recipientLimit: 0)
        #expect(warning == .malformedAddress("b@@x.com"))
    }

    @Test func aPastedAddressWithItsNameStillAttachedIsFine() {
        #expect(SendWarning.isDeliverable("Peta Bilston <peta@example.com>"))
    }

    @Test func ordinaryAddressesPass() {
        for good in ["a@x.com", "peta.bilston@sistercreatives.co",
                     "warren+velomail@living-legacy.com.au", " a@x.com "] {
            #expect(SendWarning.isDeliverable(good), "\(good) should be deliverable")
        }
    }

    @Test func theObviouslyBrokenDoNot() {
        for bad in ["", "@x.com", "a@", "a@.com", "a@x.", "plain", "a@@x.com"] {
            #expect(!SendWarning.isDeliverable(bad), "\(bad) should not be deliverable")
        }
    }

    @Test func itIsAskedBeforeTheJudgementCalls() {
        // A typo is certain to fail; a missing attachment is a guess.
        let d = draft("See the attached plan.", to: ["broken"])
        #expect(SendWarning.check(d, recipientLimit: 0) == .malformedAddress("broken"))
    }

    // MARK: - No subject

    @Test func anEmptySubjectIsWorthOneQuestion() {
        #expect(SendWarning.check(draft("hi", subject: ""), recipientLimit: 0) == .noSubject)
    }

    @Test func whitespaceIsNotASubject() {
        #expect(SendWarning.check(draft("hi", subject: "   "), recipientLimit: 0) == .noSubject)
    }

    @Test func itComesLastOfAll() {
        // A discourtesy, not a mistake: the missing file matters more.
        #expect(SendWarning.check(draft("See the attached plan.", subject: ""), recipientLimit: 0)
                == .missingAttachment)
    }

    @Test func everyWarningOffersAWayPast() {
        for warning: SendWarning in [.malformedAddress("x"), .missingAttachment,
                                     .noSubject, .manyRecipients(9)] {
            #expect(!warning.question.isEmpty)
            #expect(!warning.proceed.isEmpty)
        }
    }
}
