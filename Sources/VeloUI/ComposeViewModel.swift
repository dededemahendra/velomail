import Foundation
import SwiftUI
import VeloCore

/// The compose sheet: a draft being edited, and the send that hands it to the
/// outbound queue.
@MainActor
public final class ComposeViewModel: ObservableObject {
    @Published public var to: String = ""
    @Published public var subject: String = ""
    @Published public var body: String = ""
    @Published public private(set) var isReply = false

    private let outbound: OutboundService
    private let resolveIdentity: () -> String
    private var identity: String { resolveIdentity() }
    private var replyContext: Message?

    public init(outbound: OutboundService, identity: @escaping () -> String) {
        self.outbound = outbound
        self.resolveIdentity = identity
    }

    public convenience init(outbound: OutboundService, identity: String) {
        self.init(outbound: outbound, identity: { identity })
    }

    /// A send with no recipient is the one mistake worth blocking in the UI;
    /// everything else Gmail will tell us about.
    public var canSend: Bool { !recipients.isEmpty }

    public func startNew() {
        to = ""; subject = ""; body = ""
        isReply = false
        replyContext = nil
    }

    public func startReply(to message: Message) {
        let draft = Draft.reply(to: message, from: identity)
        to = draft.to.joined(separator: ", ")
        subject = draft.subject
        // The quote goes in the editor, not on at send time: what the user sees
        // is what gets sent, and they can trim it like in any other client.
        // Two blank lines first so the cursor has room above it.
        body = "\n\n" + QuotedReply.text(quoting: message)
        isReply = true
        replyContext = message
    }

    /// - Returns: the queued mutation id, so the caller can offer an undo.
    @discardableResult
    public func send() throws -> Int64? {
        guard canSend else { return nil }
        let draft: Draft
        if let message = replyContext {
            var reply = Draft.reply(to: message, from: identity, bodyText: body)
            reply.to = recipients
            reply.subject = subject
            draft = reply
        } else {
            draft = Draft(to: recipients, subject: subject, bodyText: body)
        }
        let queued = try outbound.send(draft, after: AppViewModel.undoWindow)
        startNew()
        return queued
    }

    // MARK: - Internals

    private var recipients: [String] {
        to.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
