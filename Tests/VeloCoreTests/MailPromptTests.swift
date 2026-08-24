import Testing
import Foundation
@testable import VeloCore

private func message(id: String = "m", sender: String = "Alice <alice@example.com>",
                     subject: String = "Lunch", text: String? = "are you free?",
                     html: String? = nil, seconds: TimeInterval = 0) -> Message {
    Message(id: id, threadID: "t", sender: sender, recipients: ["me@example.com"],
            subject: subject, date: Date(timeIntervalSince1970: seconds),
            bodyHTML: html, bodyText: text, isUnread: false, labelIDs: [])
}

@Suite struct MailPromptTests {
    // MARK: - Transcript building

    @Test func transcriptCarriesSenderAndBody() {
        let prompt = MailPrompt.transcript(of: [message()])
        #expect(prompt.contains("Alice <alice@example.com>"))
        #expect(prompt.contains("are you free?"))
    }

    @Test func transcriptKeepsMessagesInOrder() {
        let prompt = MailPrompt.transcript(of: [
            message(id: "m1", text: "first", seconds: 0),
            message(id: "m2", text: "second", seconds: 100),
        ])
        let first = try! #require(prompt.range(of: "first"))
        let second = try! #require(prompt.range(of: "second"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test func transcriptPrefersPlainTextOverHTML() {
        let prompt = MailPrompt.transcript(of: [
            message(text: "the words", html: "<div class='x'><p>the words</p></div>")])
        // Markup is most of the bytes and none of the meaning.
        #expect(prompt.contains("the words"))
        #expect(!prompt.contains("<div"))
    }

    @Test func transcriptStripsTagsWhenOnlyHTMLExists() {
        let prompt = MailPrompt.transcript(of: [message(text: nil, html: "<p>only <b>html</b></p>")])
        #expect(prompt.contains("only html"))
        #expect(!prompt.contains("<p>"))
    }

    @Test func transcriptTruncatesLongBodies() {
        let long = String(repeating: "x", count: 10_000)
        let prompt = MailPrompt.transcript(of: [message(text: long)], perMessageLimit: 500)
        #expect(prompt.count < 1_500)
    }

    @Test func truncationIsAnnouncedSoTheModelKnowsItIsPartial() {
        let prompt = MailPrompt.transcript(of: [message(text: String(repeating: "x", count: 900))],
                                           perMessageLimit: 100)
        // Otherwise the model reasons about a sentence that just stops.
        #expect(prompt.contains("[truncated]"))
    }

    @Test func shortBodiesAreNotMarkedTruncated() {
        #expect(!MailPrompt.transcript(of: [message(text: "short")]).contains("[truncated]"))
    }

    // MARK: - Operations

    @Test func summaryPromptNamesTheSubject() {
        let request = MailPrompt.summarize(messages: [message(subject: "Q3 planning")])
        #expect(request.prompt.contains("Q3 planning"))
        #expect(request.system?.isEmpty == false)
    }

    @Test func suggestedRepliesAskForOnePerLine() {
        let request = MailPrompt.suggestReplies(messages: [message()], count: 3)
        #expect(request.prompt.lowercased().contains("3"))
        #expect(request.prompt.lowercased().contains("one per line"))
    }

    @Test func draftReplyCarriesTheUsersInstruction() {
        let request = MailPrompt.draftReply(messages: [message()],
                                            instruction: "say yes but move it to Friday")
        #expect(request.prompt.contains("say yes but move it to Friday"))
    }

    @Test func rewriteNamesTheRequestedTone() {
        let request = MailPrompt.rewrite("yo", tone: .formal)
        #expect(request.prompt.contains("yo"))
        #expect(request.prompt.lowercased().contains("formal"))
    }

    @Test func everyToneHasWordingOfItsOwn() {
        // A tone that silently reads like another is a feature that does nothing.
        let prompts = WritingTone.allCases.map { MailPrompt.rewrite("x", tone: $0).prompt }
        #expect(Set(prompts).count == WritingTone.allCases.count)
    }

    @Test func translationNamesTheTargetLanguage() {
        let request = MailPrompt.translate("hello", to: "Indonesian")
        #expect(request.prompt.contains("Indonesian"))
        #expect(request.prompt.contains("hello"))
    }

    @Test func grammarPromptAsksToPreserveMeaning() {
        let request = MailPrompt.fixGrammar("i has went")
        #expect(request.prompt.contains("i has went"))
        #expect(request.system?.lowercased().contains("meaning") == true)
    }

    @Test func subjectLinePromptAsksForOneLine() {
        let request = MailPrompt.subjectLine(body: "we should meet about the plot map")
        #expect(request.prompt.contains("plot map"))
        #expect(request.maxTokens <= 64)      // a subject line is not an essay
    }

    @Test func triagePromptOffersTheFixedVocabulary() {
        let request = MailPrompt.triage(messages: [message()])
        for priority in MailPriority.allCases {
            #expect(request.prompt.lowercased().contains(priority.rawValue))
        }
    }
}
