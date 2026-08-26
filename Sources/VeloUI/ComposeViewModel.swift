import Foundation
import SwiftUI
import VeloCore

/// The compose sheet: a draft being edited, and the send that hands it to the
/// outbound queue.
public enum ComposeError: Error, Equatable {
    /// Adding this file would push the message past what Gmail accepts.
    case attachmentsTooLarge
}

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
    @Published public private(set) var attachments: [DraftAttachment] = []

    private let outbound: OutboundService
    private let resolveIdentity: () -> String
    private let library: SnippetLibrary
    private let drafts: DraftStore?
    private var identity: String { resolveIdentity() }
    private var replyContext: Message?
    /// Threading restored from a stored draft, when the parent message itself
    /// is not to hand.
    private var resumedContext: (threadID: String?, inReplyTo: String?, references: [String])?
    /// Guards the re-entry an expansion's own write to `body` would cause.
    private var isExpanding = false

    public init(outbound: OutboundService, identity: @escaping () -> String,
                library: SnippetLibrary = .empty, drafts: DraftStore? = nil) {
        self.outbound = outbound
        self.resolveIdentity = identity
        self.library = library
        self.drafts = drafts
    }

    public convenience init(outbound: OutboundService, identity: String,
                            library: SnippetLibrary = .empty, drafts: DraftStore? = nil) {
        self.init(outbound: outbound, identity: { identity }, library: library, drafts: drafts)
    }

    // MARK: - Drafts

    public var hasStoredDraft: Bool { (try? drafts?.load()) as? StoredDraft != nil }

    /// Persists what is in the composer, if it amounts to anything.
    ///
    /// Called on change rather than a timer, so what survives a crash is what
    /// was on screen a keystroke ago.
    public func autosave() {
        guard let drafts else { return }
        guard hasContent else {
            try? drafts.discard()
            return
        }
        try? drafts.save(currentDraft())
    }

    /// Puts the stored draft back in the composer. A no-op when there is none.
    public func resumeDraft() {
        guard let stored = (try? drafts?.load()) as? StoredDraft else { return }
        let draft = stored.draft
        to = draft.to.joined(separator: ", ")
        subject = draft.subject
        body = draft.bodyText
        attachments = draft.attachments
        isReply = draft.threadID != nil
        resumedContext = (threadID: draft.threadID, inReplyTo: draft.inReplyTo,
                          references: draft.references)
    }

    public func discardDraft() {
        try? drafts?.discard()
        startNew()
    }

    /// An untouched composer is not a draft. The signature is excluded because
    /// the app put it there, not the user -- otherwise opening the composer and
    /// closing it would leave a phantom draft to resume forever.
    private var hasContent: Bool {
        !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !subject.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !attachments.isEmpty
            || body.trimmingCharacters(in: .whitespacesAndNewlines)
                != signatureBlock.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A send with no recipient is the one mistake worth blocking in the UI;
    /// everything else Gmail will tell us about.
    public var canSend: Bool { !recipients.isEmpty }

    /// Reads a file off disk and attaches it.
    ///
    /// The size check happens here rather than at send: refusing a 40MB video
    /// now is a fine experience, while appearing to send it and surfacing a
    /// server error after the undo window closed is not.
    public func attach(_ url: URL) throws {
        let data = try Data(contentsOf: url)
        guard attachmentBytes + data.count <= Draft.maximumAttachmentBytes else {
            throw ComposeError.attachmentsTooLarge
        }
        attachments.append(DraftAttachment(
            filename: url.lastPathComponent,
            mimeType: DraftAttachment.mimeType(forExtension: url.pathExtension),
            data: data))
    }

    public func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
    }

    public var attachmentBytes: Int { attachments.reduce(0) { $0 + $1.data.count } }

    public func startNew() {
        to = ""; subject = ""; body = signatureBlock
        attachments = []
        isReply = false
        replyContext = nil
        resumedContext = nil
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
        let queued = try outbound.send(currentDraft(), after: AppViewModel.undoWindow)
        // The message is on its way, so there is nothing left to resume.
        try? drafts?.discard()
        startNew()
        return queued
    }

    /// The composer as a `Draft`. One builder, so what autosave stores is
    /// exactly what send would have sent.
    private func currentDraft() -> Draft {
        var draft: Draft
        if let message = replyContext {
            var reply = Draft.reply(to: message, from: identity, bodyText: body)
            reply.to = recipients
            reply.subject = subject
            draft = reply
        } else {
            draft = Draft(to: recipients, subject: subject, bodyText: body)
            // A resumed reply has no parent message to hand, so its threading
            // comes from what was stored. Losing it would turn the reply into a
            // new message to the same person.
            if let resumed = resumedContext {
                draft.threadID = resumed.threadID
                draft.inReplyTo = resumed.inReplyTo
                draft.references = resumed.references
            }
        }
        draft.attachments = attachments
        return draft
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
