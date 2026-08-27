import Foundation

/// A draft as Gmail returns it.
public struct GmailDraftDTO: Decodable, Equatable, Sendable {
    public let id: String
    /// The whole RFC 5322 message, base64url.
    public let raw: String?

    public init(id: String, raw: String?) {
        self.id = id
        self.raw = raw
    }
}

/// The draft operations Gmail offers.
public protocol GmailDrafting: Sendable {
    func listDrafts() async throws -> [GmailDraftDTO]
    /// - Returns: the new draft's id.
    func createDraft(raw: String) async throws -> String
    func updateDraft(id: String, raw: String) async throws
}

/// Keeps the local drafts and Gmail's in step.
///
/// Two directions, deliberately separate: pulling is about mail written
/// somewhere else, pushing is about mail written here, and one failing should
/// not stop the other.
public struct GmailDraftService: Sendable {
    /// Marks the local rows that came from Gmail, so a pull can remove the
    /// ones deleted there without touching a draft written here that has never
    /// been pushed.
    static let remotePrefix = "gmail:"

    private let source: GmailDrafting
    private let drafts: DraftStore
    private let identity: @Sendable () -> String

    public init(source: GmailDrafting, drafts: DraftStore,
                identity: @escaping @Sendable () -> String = { "" }) {
        self.source = source
        self.drafts = drafts
        self.identity = identity
    }

    // MARK: - Pulling

    /// Brings down what was written elsewhere.
    public func pull() async throws {
        let remote = try await source.listDrafts()
        let arrived = Set(remote.map { Self.remotePrefix + $0.id })

        for dto in remote {
            guard let raw = dto.raw, let draft = MIMEReader.draft(fromBase64URL: raw) else { continue }
            try drafts.save(draft, id: Self.remotePrefix + dto.id)
        }

        // Only rows this service owns: a draft written here and not yet pushed
        // is not Gmail's to delete.
        for stored in try drafts.all()
        where stored.id.hasPrefix(Self.remotePrefix) && !arrived.contains(stored.id) {
            try drafts.discard(id: stored.id)
        }
    }

    // MARK: - Pushing

    /// Sends up what was written here, creating each once and updating it
    /// after -- otherwise every autosave would leave another copy in Gmail.
    public func push() async throws {
        for stored in try drafts.all() where !stored.id.hasPrefix(Self.remotePrefix) {
            let draft = stored.draft
            guard !draft.isEmpty else { continue }
            let raw = MIMEBuilder.raw(draft, from: identity(),
                                      messageID: "<\(stored.id)@velomail>",
                                      date: stored.updatedAt, boundary: "velo-\(stored.id)")

            if let remoteID = try drafts.remoteID(of: stored.id) {
                try await source.updateDraft(id: remoteID, raw: raw)
            } else {
                let created = try await source.createDraft(raw: raw)
                try drafts.setRemoteID(created, on: stored.id)
            }
        }
    }
}

private extension Draft {
    /// Nothing anyone would want kept.
    var isEmpty: Bool {
        to.isEmpty && cc.isEmpty && bcc.isEmpty
            && subject.isEmpty
            && bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
