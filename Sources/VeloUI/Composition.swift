import Foundation
import VeloCore

/// The composition root: opens the store, wires the engine, and hands back a
/// ready `AppViewModel`. Kept out of the view models so they stay testable
/// against an in-memory database.
public enum Composition {
    static let redirectURI = "co.sistercreatives.velomail:/oauth2redirect"
    static let identityKey = "VELOMAIL_IDENTITY"

    /// Where the mailbox lives between launches.
    public static var databaseURL: URL {
        let base = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VeloMail", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("velomail.sqlite")
    }

    public struct Assembly {
        public let app: AppViewModel
        public let sync: GmailSync?
        public let store: MailStore
    }

    @MainActor
    public static func make(config: AppConfig = .resolve()) throws -> Assembly {
        // Demo runs in memory: it exists to be looked at, not to persist.
        let database = config.isDemo
            ? try AppDatabase.makeInMemory()
            : try AppDatabase.make(atPath: databaseURL.path)

        let store = MailStore(database)
        let mutations = MutationStore(database)
        let syncState = SyncStateStore(database)
        let identity = ProcessInfo.processInfo.environment[identityKey] ?? "me@example.com"

        if config.isDemo { try DemoData.seed(into: store) }

        guard let clientID = config.clientID else {
            // Unconfigured: still a fully working local app, just with nothing
            // to sync. A local-only writer keeps the queue honest.
            let outbound = OutboundService(writer: LocalOnlyWriter(), store: store,
                                           mutations: mutations, identity: identity)
            return Assembly(app: AppViewModel(config: config, store: store,
                                              outbound: outbound, identity: identity),
                            sync: nil, store: store)
        }

        let httpClient = URLSessionHTTPClient()
        let authConfig = AuthConfig.gmail(clientID: clientID, redirectURI: redirectURI)
        let tokenService = TokenService(config: authConfig, httpClient: httpClient)
        let tokenProvider = AccessTokenProvider(store: KeychainTokenStore(), service: tokenService)
        let api = GmailAPIClient(httpClient: httpClient, tokenProvider: tokenProvider)

        let outbound = OutboundService(writer: api, store: store, mutations: mutations, identity: identity)
        let sync = GmailSync(
            accountID: identity,
            backfill: BackfillService(source: api, store: store, syncState: syncState),
            incremental: IncrementalSyncService(source: api, store: store, syncState: syncState),
            outbound: outbound,
            syncState: syncState)

        return Assembly(app: AppViewModel(config: config, store: store,
                                          outbound: outbound, identity: identity),
                        sync: sync, store: store)
    }
}

/// Used when there are no credentials: mutations queue locally and are never
/// pushed. Throwing `AuthError` rather than succeeding keeps `drain()`'s
/// revert path honest instead of silently swallowing writes.
struct LocalOnlyWriter: GmailWriting {
    func batchModifyMessages(ids: [String], addLabelIDs: [String], removeLabelIDs: [String]) async throws {
        throw AuthError.invalidResponse
    }
    func sendMessage(raw: String, threadID: String?) async throws -> GmailMessageDTO {
        throw AuthError.invalidResponse
    }
}
