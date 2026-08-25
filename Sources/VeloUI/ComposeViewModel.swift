import Foundation
import SwiftUI
import VeloCore

/// The compose sheet: a draft being edited, and the send that hands it to the
/// outbound queue.
@MainActor
public final class ComposeViewModel: ObservableObject {
    @Published public var to: String = ""
    @Published public var subject: String = ""
    /// Observed rather than plain, because a snippet expands off the character
    /// you just typed and `TextEditor` gives no other hook to hang that on.
    @Published public var body: String = "" {
        didSet { expandIfTyped(from: oldValue) }
    }
    @Published public private(set) var isReply = false

    private let outbound: OutboundService
    private let resolveIdentity: () -> String
    private let library: SnippetLibrary
    private var identity: String { resolveIdentity() }
    private var replyContext: Message?
    /// Guards the re-entry an expansion's own write to `body` would cause.
    private var isExpanding = false

    public init(outbound: OutboundService, identity: @escaping () -> String,
                library: SnippetLibrary = .empty) {
        self.outbound = outbound
        self.resolveIdentity = identity
        self.library = library
    }

    public convenience init(outbound: OutboundService, identity: String,
                            library: SnippetLibrary = .empty) {
        self.init(outbound: outbound, identity: { identity }, library: library)
    }

    /// A send with no recipient is the one mistake worth blocking in the UI;
    /// everything else Gmail will tell us about.
    public var canSend: Bool { !recipients.isEmpty }

    public func startNew() {
        to = ""; subject = ""; body = signatureBlock
        isReply = false
        replyContext = nil
    }

    public func startReply(to message: Message) {
        let draft = Draft.reply(to: message, from: identity)
        to = draft.to.joined(separator: ", ")
        subject = draft.subject
        // The quote goes in the editor, not on at send time: what the user sees
        // is what gets sent, and they can trim it like in any other client.
        // Two blank lines first so the cursor has room above it, and the
        // signature above the quote, which is where every reader looks for it.
        body = signatureBlock + "\n\n" + QuotedReply.text(quoting: message)
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

    /// The signature, with room above it to write. Empty when none is
    /// configured, so a draft is then byte-for-byte what it was before
    /// signatures existed.
    private var signatureBlock: String {
        library.signature.map { "\n\n" + $0 } ?? ""
    }

    /// Expands a `;shortcut` when the character just typed closed it off.
    ///
    /// A template also fills the subject, but only an *empty* one: expanding a
    /// template into a reply must not silently rewrite "Re: ...".
    private func expandIfTyped(from previous: String) {
        guard !isExpanding,
              let expansion = SnippetExpansion.expandOnTyping(previous: previous, current: body,
                                                              using: library) else { return }
        isExpanding = true
        body = expansion.text
        isExpanding = false
        if let templateSubject = expansion.snippet.subject, subject.isEmpty {
            subject = templateSubject
        }
    }

    private var recipients: [String] {
        to.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
