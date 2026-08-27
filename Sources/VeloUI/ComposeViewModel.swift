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
    @Published public var to: String = "" {
        // The list underneath has changed, so a kept highlight would point at
        // whoever now happens to sit in that row.
        didSet {
            guard to != oldValue else { return }
            highlighted = 0
            isSuggesting = true
        }
    }

    /// False once the list has been dismissed, until more is typed.
    @Published private var isSuggesting = true

    /// Which suggestion the keyboard is currently on.
    @Published public private(set) var highlighted = 0
    @Published public var cc: String = ""
    /// Recipients the others cannot see. Kept out of the way behind a control,
    /// because a Bcc field left standing open is how one gets used by accident.
    @Published public var bcc: String = ""
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
    /// Mints the id for a fresh draft. Injectable so tests can name them.
    private let newDraftID: () -> String
    /// Which stored draft this composer is editing. A fresh one per compose, so
    /// starting a second message cannot overwrite the first.
    private var draftID: String
    /// Built once per composed message rather than per keystroke: it reads a
    /// year of mail, which is cheap once and not cheap sixty times a minute.
    private let contacts: (() -> AddressBook?)?
    /// Read at send time, so a change in settings applies to the next message
    /// rather than the next launch. Injected so a test's isolated preferences
    /// reach the composer rather than stopping at the app.
    private let preferences: AppPreferences
    /// Finds the message a resumed draft is answering. Without it a reply put
    /// down and picked up again would go out unquoted, with nothing to say one
    /// was ever meant to be there.
    private let parentLookup: ((String) -> Message?)?
    /// The quoted message's inline parts, for the expander to resolve `cid:`.
    private let attachmentLookup: ((String) -> [MailAttachment])?
    private var addressBook: AddressBook?
    private var identity: String { resolveIdentity() }
    private var replyContext: Message?
    /// Threading restored from a stored draft, when the parent message itself
    /// is not to hand.
    private var resumedContext: (threadID: String?, inReplyTo: String?, references: [String])?
    /// Whether the parent goes out under what is being written. On by default,
    /// because a reply that drops the thread reads as a non-sequitur to anyone
    /// who has to remember what they asked.
    @Published public var includesQuote = true

    /// Guards the re-entry an expansion's own write to `body` would cause.
    private var isExpanding = false

    public init(outbound: OutboundService, identity: @escaping () -> String,
                library: SnippetLibrary = .empty, drafts: DraftStore? = nil,
                addressBook: AddressBook? = nil,
                contacts: (() -> AddressBook?)? = nil,
                parentLookup: ((String) -> Message?)? = nil,
                attachmentLookup: ((String) -> [MailAttachment])? = nil,
                newDraftID: @escaping () -> String = { UUID().uuidString },
                preferences: AppPreferences = AppPreferences()) {
        self.preferences = preferences
        self.parentLookup = parentLookup
        self.attachmentLookup = attachmentLookup
        self.newDraftID = newDraftID
        self.draftID = newDraftID()
        self.outbound = outbound
        self.resolveIdentity = identity
        self.library = library
        self.drafts = drafts
        self.addressBook = addressBook
        self.contacts = contacts
    }

    public convenience init(outbound: OutboundService, identity: String,
                            library: SnippetLibrary = .empty, drafts: DraftStore? = nil,
                            addressBook: AddressBook? = nil,
                            contacts: (() -> AddressBook?)? = nil,
                            parentLookup: ((String) -> Message?)? = nil,
                            attachmentLookup: ((String) -> [MailAttachment])? = nil,
                            newDraftID: @escaping () -> String = { UUID().uuidString },
                            preferences: AppPreferences = AppPreferences()) {
        self.init(outbound: outbound, identity: { identity }, library: library,
                  drafts: drafts, addressBook: addressBook, contacts: contacts,
                  parentLookup: parentLookup, attachmentLookup: attachmentLookup,
                  newDraftID: newDraftID, preferences: preferences)
    }

    // MARK: - Drafts

    /// Contacts matching whatever address is being typed right now.
    ///
    /// Only the fragment after the last comma is matched -- an address already
    /// completed must not keep suggesting itself.
    public var suggestions: [AddressBook.Contact] {
        guard isSuggesting, let addressBook else { return [] }
        return addressBook.suggestions(for: Self.fragment(of: to))
    }

    /// Puts the list away without changing what has been typed.
    public func dismissSuggestions() { isSuggesting = false }

    /// Moves the highlight, wrapping at both ends so a held arrow key never
    /// appears to stall.
    public func moveHighlight(by offset: Int) {
        let count = suggestions.count
        guard count > 0 else { highlighted = 0; return }
        highlighted = ((highlighted + offset) % count + count) % count
    }

    /// Takes the highlighted contact, reporting whether there was one.
    ///
    /// The caller uses the answer to decide whether the key was theirs: with no
    /// suggestions showing, Return still has to reach the composer.
    @discardableResult
    public func acceptHighlighted() -> Bool {
        let matches = suggestions
        guard matches.indices.contains(highlighted) else { return false }
        accept(matches[highlighted])
        return true
    }

    /// Rereads the address book for a newly opened composer.
    private func refreshContacts() {
        if let contacts { addressBook = contacts() }
    }

    /// Replaces the fragment being typed with the chosen contact, leaving a
    /// separator so the next address can follow immediately.
    public func accept(_ contact: AddressBook.Contact) {
        var parts = to.components(separatedBy: ",").dropLast().map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        parts.append(contact.label)
        to = parts.joined(separator: ", ") + ", "
        autosave()
    }

    static func fragment(of field: String) -> String {
        (field.components(separatedBy: ",").last ?? "").trimmingCharacters(in: .whitespaces)
    }

    /// What the composer calls itself, so a forward does not claim to be a
    /// reply and a reply-all does not look like a reply.
    public var headline: String {
        if isReply { return cc.isEmpty ? "Reply" : "Reply all" }
        return subject.lowercased().hasPrefix("fwd:") ? "Forward" : "New message"
    }

    public var hasStoredDraft: Bool { storedDraft != nil }

    /// Persists what is in the composer, if it amounts to anything.
    ///
    /// Called on change rather than a timer, so what survives a crash is what
    /// was on screen a keystroke ago.
    public func autosave() {
        guard let drafts else { return }
        guard hasContent else {
            try? drafts.discard(id: draftID)
            return
        }
        // Without the quote: a draft is what was typed, and storing the parent
        // with it would grow every autosave by the size of the message being
        // answered. The quote is re-attached from the parent at send.
        try? drafts.save(currentDraft(quoting: false), id: draftID)
    }

    /// Loads a draft into the composer, threading and all.
    ///
    /// Used by resume and by reopening a send that never went: both are the
    /// same act of putting written words back in front of the writer.
    public func resume(_ draft: Draft) {
        refreshContacts()
        // Re-finding the parent is what lets a resumed reply still quote.
        replyContext = draft.threadID.flatMap { parentLookup?($0) }
        includesQuote = replyContext != nil
        // A draft handed over without a row of its own -- a reopened failed
        // send -- becomes a new one rather than claiming someone else's id.
        draftID = newDraftID()
        to = draft.to.joined(separator: ", ")
        cc = draft.cc.joined(separator: ", ")
        bcc = draft.bcc.joined(separator: ", ")
        subject = draft.subject
        body = draft.bodyText
        attachments = draft.attachments
        isReply = draft.threadID != nil
        resumedContext = (threadID: draft.threadID, inReplyTo: draft.inReplyTo,
                          references: draft.references)
    }

    /// Puts a stored draft back in the composer, keeping its identity so
    /// further edits update that row rather than forking a copy.
    public func resume(_ stored: StoredDraft) {
        resume(stored.draft)
        draftID = stored.id
    }

    /// Resumes what was being written most recently. A no-op when there is none.
    public func resumeDraft() {
        guard let stored = storedDraft else { return }
        resume(stored)
    }

    /// Every draft in flight, most recently touched first.
    public var storedDrafts: [StoredDraft] { (try? drafts?.all()) as? [StoredDraft] ?? [] }

    /// Flattens the double optional a `try?` on an optional store produces.
    private var storedDraft: StoredDraft? {
        guard let drafts, let stored = try? drafts.latest() else { return nil }
        return stored
    }

    /// Bins the draft on screen. The others are untouched.
    public func discardDraft() {
        try? drafts?.discard(id: draftID)
        startNew()
    }

    /// Bins a named draft without disturbing what is being written.
    public func discard(_ stored: StoredDraft) {
        try? drafts?.discard(id: stored.id)
        if stored.id == draftID { startNew() }
    }

    /// An untouched composer is not a draft. The signature is excluded because
    /// the app put it there, not the user -- otherwise opening the composer and
    /// closing it would leave a phantom draft to resume forever.
    private var hasContent: Bool {
        !to.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !cc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
    /// Attaches several files, keeping what worked.
    ///
    /// - Returns: the names that could not be attached, so the caller can say
    ///   which. Dropping five files and getting none because one was
    ///   unreadable is worse than getting four and being told.
    @discardableResult
    public func attach(_ urls: [URL]) -> [String] {
        var failed: [String] = []
        for url in urls {
            do {
                try attach(url)
            } catch {
                failed.append(url.lastPathComponent)
            }
        }
        return failed
    }

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
        refreshContacts()
        // A new message is a new row. Reusing the id is exactly how the last
        // half-written one used to be overwritten.
        draftID = newDraftID()
        to = ""; cc = ""; bcc = ""; subject = ""; body = signatureBlock
        attachments = []
        isReply = false
        replyContext = nil
        resumedContext = nil
    }

    /// A reply to everyone on the message, minus you.
    public func startReplyAll(to message: Message) {
        startReply(to: message)
        cc = Draft.replyAll(to: message, from: identity).cc.joined(separator: ", ")
    }

    /// Forwards `message` to somebody new, carrying its files.
    ///
    /// Not a reply: `replyContext` stays nil so the sent draft is not threaded,
    /// which would otherwise deliver the forward to the original participants.
    public func startForward(of message: Message, attachments files: [DraftAttachment]) {
        refreshContacts()
        let draft = Draft.forward(message, from: identity, attachments: files)
        to = ""
        cc = ""
        bcc = ""
        subject = draft.subject
        body = draft.bodyText
        attachments = files
        isReply = false
        replyContext = nil
        resumedContext = nil
    }

    public func startReply(to message: Message) {
        refreshContacts()
        let draft = Draft.reply(to: message, from: identity)
        to = draft.to.joined(separator: ", ")
        cc = ""
        bcc = ""
        subject = draft.subject
        // The quote is attached at send time rather than pasted here. It used
        // to go in the editor on the reasoning that what you see is what gets
        // sent -- but on real mail that means scrolling past twenty lines of
        // someone else's tracking URLs to reach your own cursor. It is shown
        // collapsed instead, and can be dropped.
        body = signatureBlock
        includesQuote = preferences.quotesByDefault
        isReply = true
        replyContext = message
    }

    /// - Returns: the queued mutation id, so the caller can offer an undo.
    @discardableResult
    public func send() throws -> Int64? {
        try send(after: preferences.undoWindow)
    }

    /// Queues the message to go at `moment` rather than in a few seconds.
    ///
    /// The same path as an ordinary send: the queue has always understood "not
    /// yet", and an undo window is only a very short version of this.
    @discardableResult
    public func send(at moment: Date, now: Date = Date()) throws -> Int64? {
        try send(after: max(moment.timeIntervalSince(now), preferences.undoWindow))
    }

    @discardableResult
    private func send(after delay: TimeInterval) throws -> Int64? {
        guard canSend else { return nil }
        let queued = try outbound.send(currentDraft(), after: delay)
        // This message is on its way, so its draft has nothing left to hold.
        // Only this one: the others are still being written.
        try? drafts?.discard(id: draftID)
        startNew()
        return queued
    }

    /// The message being answered, in a line: who and when.
    ///
    /// Nil when there is nothing quoted, which is what the composer keys the
    /// whole strip off.
    public var quotedSummary: String? {
        guard let message = replyContext else { return nil }
        return "\(MailFormatting.displayName(message.sender)), "
            + "\(ComposeViewModel.quoteDate.string(from: message.date))"
    }

    /// The message being answered, for the expander to render as itself.
    ///
    /// The message rather than text: the expander shows it through the same
    /// view the thread pane uses, so the quote looks like the mail it came
    /// from instead of a re-typed approximation of it.
    public var quotedMessage: Message? { replyContext }

    /// The quoted message's own parts, so pictures it brought with it still
    /// appear. They carry their own bytes and fetch nothing.
    public var quotedAttachments: [MailAttachment] {
        guard let id = replyContext?.id else { return [] }
        return attachmentLookup?(id) ?? []
    }

    /// The quoted parent as plain text. Still needed for the `text/plain` half
    /// of what goes out, whatever the composer shows.
    public var quotedPreview: String? {
        replyContext.map { QuotedReply.preview(of: $0) }
    }

    private static let quoteDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "d MMM yyyy"
        return formatter
    }()

    /// True when what has been typed will be sent as HTML as well as text.
    public var isRichText: Bool { MarkdownBody.isFormatted(body) }

    /// What would be sent right now, for anything that has to look at a
    /// message before it goes.
    public var pendingDraft: Draft { currentDraft() }

    /// The composer as a `Draft`. One builder, so what autosave stores is
    /// exactly what send would have sent.
    private func currentDraft(quoting: Bool? = nil) -> Draft {
        let quotes = quoting ?? includesQuote
        var draft: Draft
        // Marks the writer typed travel as HTML; the plain part keeps what was
        // typed, which is what a reader on a text-only client expects to see.
        let html = MarkdownBody.html(from: body)
        if let message = replyContext {
            // `quoting:` builds both halves from the parent itself, so the HTML
            // quote is the sender's own markup rather than a plain-text
            // rendition of a message that had better to offer.
            var reply = Draft.reply(to: message, from: identity, bodyText: body,
                                    bodyHTML: html, quoting: quotes)
            reply.to = recipients
            reply.cc = addresses(in: cc)
            reply.bcc = addresses(in: bcc)
            reply.subject = subject
            draft = reply
        } else {
            draft = Draft(to: recipients, cc: addresses(in: cc), bcc: addresses(in: bcc),
                          subject: subject, bodyText: body, bodyHTML: html)
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

    private var recipients: [String] { addresses(in: to) }

    private func addresses(in field: String) -> [String] {
        field.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
