import Testing
import Foundation
import VeloCore
@testable import VeloUI

@Suite struct ThreadExportTests {
    private func msg(_ id: String, from: String = "peta@example.com",
                     subject: String = "Revised invoice",
                     text: String? = "The planting moved to the 14th.",
                     html: String? = nil, cc: [String] = []) -> Message {
        Message(id: id, threadID: "t", sender: from, recipients: ["warren@example.com"],
                cc: cc, subject: subject, date: Date(timeIntervalSince1970: 1_700_000_000),
                bodyHTML: html, bodyText: text, isUnread: false, labelIDs: [])
    }

    // MARK: - What comes out

    @Test func everyMessageIsThereInOrder() {
        let text = ThreadExport.plainText(of: [msg("m0", text: "First"), msg("m1", text: "Second")])
        let first = try! #require(text.range(of: "First"))
        let second = try! #require(text.range(of: "Second"))
        #expect(first.lowerBound < second.lowerBound)
    }

    @Test func eachOneCarriesWhoItWasFromAndTo() {
        let text = ThreadExport.plainText(of: [msg("m0")])
        #expect(text.contains("From: peta@example.com"))
        #expect(text.contains("To: warren@example.com"))
        #expect(text.contains("Subject: Revised invoice"))
    }

    @Test func ccIsOnlyThereWhenThereIsOne() {
        #expect(!ThreadExport.plainText(of: [msg("m0")]).contains("Cc:"))
        #expect(ThreadExport.plainText(of: [msg("m0", cc: ["salsa@example.com"])])
            .contains("Cc: salsa@example.com"))
    }

    @Test func anHTMLOnlyMessageComesOutAsWords() {
        let text = ThreadExport.plainText(of: [msg("m0", text: nil, html: "<p>Hello <b>there</b></p>")])
        #expect(text.contains("Hello"))
        #expect(!text.contains("<b>"))
    }

    @Test func aMessageWithNothingInItSaysSoRatherThanLeavingAGap() {
        #expect(ThreadExport.plainText(of: [msg("m0", text: nil)]).contains("(no text)"))
    }

    // MARK: - What it is called

    @Test func theFileIsNamedAfterTheConversation() {
        #expect(ThreadExport.fileName(for: [msg("m0")], threadID: "t1") == "Revised invoice.txt")
    }

    @Test func aSlashInASubjectDoesNotBecomeADirectory() {
        let name = ThreadExport.fileName(for: [msg("m0", subject: "Invoice 9/2026")], threadID: "t1")
        #expect(!name.contains("/"))
        #expect(name.hasSuffix(".txt"))
    }

    @Test func aSubjectlessThreadIsStillSaveable() {
        // An empty stem would make a dotfile.
        #expect(ThreadExport.fileName(for: [msg("m0", subject: "")], threadID: "t1") == "t1.txt")
        #expect(ThreadExport.fileName(for: [msg("m0", subject: "  ")], threadID: "t1") == "t1.txt")
    }

    @Test func aVeryLongSubjectIsCutToSomethingAFilesystemAccepts() {
        let long = String(repeating: "a", count: 400)
        let name = ThreadExport.fileName(for: [msg("m0", subject: long)], threadID: "t1")
        #expect(name.count <= 64)
    }

    // MARK: - Writing it

    @Test func writingTwiceNumbersRatherThanOverwrites() throws {
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("velo-export-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }

        let first = try ThreadExport.write("one", named: "Notes.txt", into: dir)
        let second = try ThreadExport.write("two", named: "Notes.txt", into: dir)

        #expect(first != second)
        #expect(try String(contentsOf: first, encoding: .utf8) == "one")
        #expect(try String(contentsOf: second, encoding: .utf8) == "two")
    }
}
