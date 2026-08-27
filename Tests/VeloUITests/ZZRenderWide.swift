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
@Suite(.serialized) struct ZZRenderWide {
    @Test func render() throws {
        guard ProcessInfo.processInfo.environment["RENDER"] != nil else { return }
        let names = ["Clients", "Somerville", "Invoices to pay", "Wellington Dam",
                     "Mornington Green", "Needs a decision", "Archive later"]
        let known = names.enumerated().map { MailLabel(id: "L\($0.offset)", name: $0.element, kind: .user) }
        let thread = MailThread(id: "t1", sender: "peta@example.com", snippet: "",
                                lastMessageDate: Date(), isUnread: false, hasAttachments: true,
                                labelIDs: ["INBOX"] + known.map(\.id))
        let msg = Message(id: "m0", threadID: "t1", sender: "Peta <peta@example.com>",
                          recipients: ["w@x.com"],
                          subject: "Invoice for the Somerville planting, revised after the site visit",
                          date: Date(), bodyHTML: nil, bodyText: "Hi", isUnread: false, labelIDs: [])
        let view = ThreadView(thread: thread, messages: [msg], isExpanded: { _ in false },
                              onToggle: { _ in }, attachments: { _ in [] },
                              attachmentModel: AttachmentViewModel(service: AttachmentService(source: NoSource())),
                              knownLabels: known, onUnsubscribe: {})
            .frame(width: 460, height: 150)
        let host = NSHostingView(rootView: view)
        host.appearance = NSAppearance(named: .aqua)
        host.frame = NSRect(x: 0, y: 0, width: 460, height: 150)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        let out = "/private/tmp/claude-501/-Users-warrenroberts-orca-velomail/9220c0f0-24bc-45cd-b5a4-1485ffa303f6/scratchpad/wide.png"
        try rep.representation(using: NSBitmapImageRep.FileType.png, properties: [:])!
            .write(to: URL(fileURLWithPath: out))
    }
}
