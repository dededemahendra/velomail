import Testing
import SwiftUI
import AppKit
import Foundation
import VeloCore
@testable import VeloUI

private final class NoSource: GmailReading, @unchecked Sendable {
    func getProfile() async throws -> GmailProfile { fatalError() }
    func listMessageIDs(labelID: String, pageToken: String?) async throws -> (ids: [String], nextPageToken: String?) { fatalError() }
    func getMessage(id: String) async throws -> GmailMessageDTO { fatalError() }
    func fetchHistory(startHistoryId: String, pageToken: String?) async throws -> GmailHistoryResponse { fatalError() }
    func getAttachment(messageID: String, attachmentID: String) async throws -> String { fatalError() }
}

@MainActor
@Suite(.serialized) struct ZZRenderThread {
    @Test func render() throws {
        guard ProcessInfo.processInfo.environment["RENDER"] != nil else { return }
        let thread = MailThread(id: "t1", sender: "peta@example.com", snippet: "",
                                lastMessageDate: Date(), isUnread: false, hasAttachments: true,
                                labelIDs: ["INBOX", "Label_7", "CATEGORY_UPDATES"])
        let senders = ["Peta Bilston <peta@example.com>", "Warren Roberts <warren@example.com>",
                       "Peta Bilston <peta@example.com>"]
        let bodies = ["Revised invoice attached, the planting moved to the 14th.",
                      "Thanks Peta, that works. Confirming the new date with Salsa.",
                      "Confirmed. See you on the 14th."]
        let msgs = (0..<3).map { i in
            Message(id: "m\(i)", threadID: "t1", sender: senders[i],
                    recipients: ["warren@example.com"],
                    subject: "Invoice for the Somerville planting, revised",
                    date: Date().addingTimeInterval(Double(i) * 600),
                    bodyHTML: nil, bodyText: bodies[i], isUnread: false, labelIDs: [])
        }
        let known = [MailLabel(id: "Label_7", name: "Clients", kind: .user),
                     MailLabel(id: "CATEGORY_UPDATES", name: "CATEGORY_UPDATES", kind: .system)]
        let view = ThreadView(thread: thread, messages: msgs, isExpanded: { _ in false },
                              onToggle: { _ in },
                              attachments: { id in
                                  id == "m0" ? [MailAttachment(id: "a", messageID: "m0", filename: "invoice.pdf",
                                                               mimeType: "application/pdf", size: 1024,
                                                               attachmentID: "x", inlineData: nil)] : [] },
                              attachmentModel: AttachmentViewModel(service: AttachmentService(source: NoSource())),
                              knownLabels: known, onUnsubscribe: {})
            .frame(width: 720, height: 260)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 720, height: 260)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let out = "/private/tmp/claude-501/-Users-warrenroberts-orca-velomail/9220c0f0-24bc-45cd-b5a4-1485ffa303f6/scratchpad/thread.png"
        try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
    }
}
