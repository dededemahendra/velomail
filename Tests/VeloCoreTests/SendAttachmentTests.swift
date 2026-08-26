import Testing
import Foundation
@testable import VeloCore

private let fixedDate = Date(timeIntervalSince1970: 1_755_600_000)
private let fixedMessageID = "<velo-1@mail.example.com>"

private func pdf(_ name: String = "invoice.pdf", bytes: Int = 5) -> DraftAttachment {
    DraftAttachment(filename: name, mimeType: "application/pdf",
                    data: Data(repeating: 0x41, count: bytes))
}

private func serialize(_ draft: Draft) -> String {
    MIMEBuilder.serialize(draft, from: "me@example.com", messageID: fixedMessageID,
                          date: fixedDate, boundary: "OUTER")
}

private func header(_ name: String, in message: String) -> String? {
    message.components(separatedBy: "\r\n")
        .first { $0.lowercased().hasPrefix(name.lowercased() + ":") }
        .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
}

@Suite struct SendAttachmentTests {
    // MARK: - Structure

    @Test func aMessageWithNoFilesIsUnchanged() {
        let plain = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        #expect(header("Content-Type", in: serialize(plain)) == "text/plain; charset=\"UTF-8\"")
    }

    @Test func filesWrapTheMessageInMultipartMixed() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf()]

        #expect(header("Content-Type", in: serialize(draft))
                == "multipart/mixed; boundary=\"OUTER\"")
    }

    @Test func theHTMLAlternativeIsNestedInsideMixedNotFlattened() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "plain", bodyHTML: "<p>rich</p>")
        draft.attachments = [pdf()]
        let message = serialize(draft)

        // Flattening tells the recipient the PDF is an alternative rendering of
        // the message, so their client shows the PDF *instead of* the text.
        #expect(message.contains("multipart/alternative"))
        let mixed = message.range(of: "multipart/mixed")!
        let alternative = message.range(of: "multipart/alternative")!
        #expect(mixed.lowerBound < alternative.lowerBound)
    }

    @Test func theInnerAndOuterBoundariesDiffer() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "plain", bodyHTML: "<p>rich</p>")
        draft.attachments = [pdf()]
        let message = serialize(draft)

        // Reusing one boundary terminates the outer part early and truncates
        // the message for every recipient.
        let inner = message.range(of: "multipart/alternative; boundary=\"")!
        let innerBoundary = String(message[inner.upperBound...].prefix(while: { $0 != "\"" }))
        #expect(innerBoundary != "OUTER")
        #expect(!innerBoundary.isEmpty)
    }

    @Test func aPlainTextMessageWithFilesPutsTextFirst() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf()]
        let message = serialize(draft)

        let text = message.range(of: "text/plain")!
        let file = message.range(of: "application/pdf")!
        #expect(text.lowerBound < file.lowerBound)
    }

    @Test func everyFileBecomesItsOwnPart() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf("one.pdf"),
                             DraftAttachment(filename: "two.png", mimeType: "image/png",
                                             data: Data([0x89, 0x50]))]
        let message = serialize(draft)

        #expect(message.contains("one.pdf"))
        #expect(message.contains("two.png"))
        #expect(message.contains("image/png"))
    }

    @Test func theMessageEndsWithTheOuterTerminator() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf()]
        #expect(serialize(draft).hasSuffix("--OUTER--"))
    }

    // MARK: - Part headers

    @Test func filesAreMarkedAsAttachmentsWithTheirName() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf()]

        #expect(serialize(draft).contains("Content-Disposition: attachment; filename=\"invoice.pdf\""))
    }

    @Test func filesAreBase64Encoded() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf(bytes: 3)]

        let message = serialize(draft)
        #expect(message.contains("Content-Transfer-Encoding: base64"))
        #expect(message.contains(Data(repeating: 0x41, count: 3).base64EncodedString()))
    }

    @Test func aNonASCIIFilenameIsEncodedRatherThanEmittedRaw() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf("résumé.pdf")]

        let message = serialize(draft)
        // Content-Disposition is an ASCII-only header.
        #expect(message.contains("=?UTF-8?B?"))
        #expect(!message.contains("résumé.pdf"))
    }

    @Test func longAttachmentsAreWrappedAt76Columns() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf(bytes: 500)]

        let lines = serialize(draft).components(separatedBy: "\r\n")
        #expect(lines.allSatisfy { $0.count <= 76 })
    }

    // MARK: - Size

    @Test func totalSizeCountsEveryAttachment() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf(bytes: 100), pdf(bytes: 250)]
        #expect(draft.attachmentBytes == 350)
    }

    @Test func aDraftWithinTheLimitIsSendable() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf(bytes: 1_000)]
        #expect(draft.exceedsAttachmentLimit == false)
    }

    @Test func anOversizedDraftIsRefusedBeforeItIsSent() {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf(bytes: Draft.maximumAttachmentBytes + 1)]

        // Better than appearing to send and failing after the undo window shut.
        #expect(draft.exceedsAttachmentLimit)
    }

    @Test func theLimitLeavesRoomForBase64Inflation() {
        // Gmail caps the request near 35MB and base64 costs a third.
        #expect(Draft.maximumAttachmentBytes < 35 * 1_000_000 * 3 / 4)
    }

    @Test func attachmentsSurviveEncodingIntoTheQueue() throws {
        var draft = Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")
        draft.attachments = [pdf()]

        let restored = try JSONDecoder().decode(
            Draft.self, from: try JSONEncoder().encode(draft))

        // The queue promises a send survives a restart; a file path would not.
        #expect(restored.attachments == draft.attachments)
    }
}
