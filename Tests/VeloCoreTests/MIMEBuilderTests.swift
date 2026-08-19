import Testing
import Foundation
@testable import VeloCore

private let fixedDate = Date(timeIntervalSince1970: 1_755_600_000)
private let fixedMessageID = "<velo-1@mail.example.com>"
private let fixedBoundary = "velo-boundary-1"

private func serialize(_ draft: Draft, from: String = "me@example.com") -> String {
    MIMEBuilder.serialize(draft, from: from, messageID: fixedMessageID,
                          date: fixedDate, boundary: fixedBoundary)
}

private func header(_ name: String, in message: String) -> String? {
    message
        .components(separatedBy: "\r\n")
        .first { $0.lowercased().hasPrefix(name.lowercased() + ":") }
        .map { String($0.dropFirst(name.count + 1)).trimmingCharacters(in: .whitespaces) }
}

@Suite struct MIMEBuilderTests {
    @Test func buildsPlainTextMessageWithRequiredHeaders() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi"))
        #expect(header("From", in: out) == "me@example.com")
        #expect(header("To", in: out) == "a@b.com")
        #expect(header("Subject", in: out) == "Hello")
        #expect(header("Date", in: out) == "Tue, 19 Aug 2025 10:40:00 +0000")
        #expect(header("Message-ID", in: out) == fixedMessageID)
        #expect(header("MIME-Version", in: out) == "1.0")
        #expect(header("Content-Type", in: out) == "text/plain; charset=\"UTF-8\"")
        #expect(header("Content-Transfer-Encoding", in: out) == "base64")
    }

    @Test func bodyIsBase64EncodedAfterABlankLine() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi"))
        #expect(out.hasSuffix("\r\n\r\naGk="))
    }

    @Test func usesCRLFLineEndingsThroughout() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "Hello", bodyText: "hi"))
        // Every LF must be preceded by a CR.
        let chars = Array(out)
        for (index, character) in chars.enumerated() where character == "\n" {
            #expect(index > 0 && chars[index - 1] == "\r")
        }
        #expect(out.contains("\r\n"))
    }

    @Test func joinsMultipleRecipientsWithCommas() {
        let out = serialize(Draft(to: ["a@b.com", "Bob <bob@x.com>"], subject: "s", bodyText: "hi"))
        #expect(header("To", in: out) == "a@b.com, Bob <bob@x.com>")
    }

    @Test func encodesNonASCIISubjectAsRFC2047EncodedWord() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "Café", bodyText: "hi"))
        #expect(header("Subject", in: out) == "=?UTF-8?B?Q2Fmw6k=?=")
    }

    @Test func leavesASCIISubjectUnencoded() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "Plain ASCII", bodyText: "hi"))
        #expect(header("Subject", in: out) == "Plain ASCII")
    }

    @Test func omitsEmptyCcAndBccHeaders() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "s", bodyText: "hi"))
        #expect(header("Cc", in: out) == nil)
        #expect(header("Bcc", in: out) == nil)
    }

    @Test func emitsCcAndBccWhenPresent() {
        let draft = Draft(to: ["a@b.com"], cc: ["c@d.com"], bcc: ["e@f.com"],
                          subject: "s", bodyText: "hi")
        #expect(header("Cc", in: serialize(draft)) == "c@d.com")
        #expect(header("Bcc", in: serialize(draft)) == "e@f.com")
    }

    @Test func omitsReplyHeadersOnANewCompose() {
        let out = serialize(Draft(to: ["a@b.com"], subject: "s", bodyText: "hi"))
        #expect(header("In-Reply-To", in: out) == nil)
        #expect(header("References", in: out) == nil)
    }

    @Test func emitsInReplyToAndSpaceJoinedReferencesWhenReplying() {
        let draft = Draft(to: ["a@b.com"], subject: "Re: s", bodyText: "hi",
                          threadID: "t1", inReplyTo: "<p@x.com>",
                          references: ["<root@x.com>", "<p@x.com>"])
        let out = serialize(draft)
        #expect(header("In-Reply-To", in: out) == "<p@x.com>")
        #expect(header("References", in: out) == "<root@x.com> <p@x.com>")
    }

    @Test func emitsMultipartAlternativeWithTextPartFirstWhenHTMLPresent() {
        let draft = Draft(to: ["a@b.com"], subject: "s",
                          bodyText: "plain body", bodyHTML: "<b>hi</b>")
        let out = serialize(draft)
        #expect(header("Content-Type", in: out)
                == "multipart/alternative; boundary=\"\(fixedBoundary)\"")

        let textPart = out.range(of: "text/plain")
        let htmlPart = out.range(of: "text/html")
        #expect(textPart != nil && htmlPart != nil)
        #expect(textPart!.lowerBound < htmlPart!.lowerBound)

        #expect(out.contains("cGxhaW4gYm9keQ=="))
        #expect(out.contains("PGI+aGk8L2I+"))
        #expect(out.hasSuffix("--\(fixedBoundary)--"))
    }

    @Test func wrapsLongBase64BodiesAt76Columns() {
        let draft = Draft(to: ["a@b.com"], subject: "s",
                          bodyText: String(repeating: "a", count: 500))
        let out = serialize(draft)
        let bodyLines = out.components(separatedBy: "\r\n\r\n")[1]
            .components(separatedBy: "\r\n")
        #expect(bodyLines.count > 1)
        #expect(bodyLines.allSatisfy { $0.count <= 76 })
    }

    @Test func rawIsBase64URLWithoutPadding() {
        let raw = MIMEBuilder.raw(Draft(to: ["a@b.com"], subject: "s", bodyText: "hi"),
                                  from: "me@example.com", messageID: fixedMessageID,
                                  date: fixedDate, boundary: fixedBoundary)
        #expect(!raw.contains("="))
        #expect(!raw.contains("+"))
        #expect(!raw.contains("/"))

        // Round-trips back to the serialized message.
        var padded = raw.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if padded.count % 4 > 0 { padded += String(repeating: "=", count: 4 - padded.count % 4) }
        let decoded = String(decoding: Data(base64Encoded: padded)!, as: UTF8.self)
        #expect(decoded == serialize(Draft(to: ["a@b.com"], subject: "s", bodyText: "hi")))
    }
}
