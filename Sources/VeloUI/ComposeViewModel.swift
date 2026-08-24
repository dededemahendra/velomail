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
        body = ""
        isReply = true
        replyContext = message
    }

    public func send() throws {
        guard canSend else { return }
        let draft: Draft
        if let message = replyContext {
            var reply = Draft.reply(to: message, from: identity, bodyText: body)
            reply.to = recipients
            reply.subject = subject
            draft = reply
        } else {
            draft = Draft(to: recipients, subject: subject, bodyText: body)
        }
        try outbound.send(draft)
        startNew()
    }

    // MARK: - Internals

    private var recipients: [String] {
        to.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
