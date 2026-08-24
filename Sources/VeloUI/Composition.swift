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
        public let auth: AuthCoordinator?
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
        // The account id is stable and local; the *address* is discovered from
        // Gmail's profile on first backfill. Keeping them separate is what lets
        // the app be built before it knows who it is.
        let accountID = "primary"
        let configuredIdentity = ProcessInfo.processInfo.environment[identityKey]
        let resolver = IdentityResolver(syncState: syncState, accountID: accountID,
                                        configured: configuredIdentity)

        if config.isDemo { try DemoData.seed(into: store) }

        guard let clientID = config.clientID else {
            // Unconfigured: still a fully working local app, just with nothing
            // to sync. A local-only writer keeps the queue honest.
            let outbound = OutboundService(writer: LocalOnlyWriter(), store: store,
                                           mutations: mutations, identity: resolver.identity)
            return Assembly(app: AppViewModel(config: config, store: store,
                                              outbound: outbound, identity: resolver.identity),
                            sync: nil, store: store, auth: nil)
        }

        let httpClient = URLSessionHTTPClient()
        let authConfig = AuthConfig.gmail(clientID: clientID, redirectURI: redirectURI)
        let tokenService = TokenService(config: authConfig, httpClient: httpClient)
        let tokenStore = KeychainTokenStore()
        let tokenProvider = AccessTokenProvider(store: tokenStore, service: tokenService)
        let api = GmailAPIClient(httpClient: httpClient, tokenProvider: tokenProvider)

        let outbound = OutboundService(writer: api, store: store, mutations: mutations,
                                       identity: resolver.identity)
        let sync = GmailSync(
            accountID: accountID,
            backfill: BackfillService(source: api, store: store, syncState: syncState),
            incremental: IncrementalSyncService(source: api, store: store, syncState: syncState),
            outbound: outbound,
            syncState: syncState)

        let auth = AuthCoordinator(config: authConfig, tokenService: tokenService, tokenStore: tokenStore)
        let app = AppViewModel(config: config, store: store, outbound: outbound,
                               identity: resolver.identity, isSignedIn: auth.state == .signedIn)
        return Assembly(app: app, sync: sync, store: store, auth: auth)
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
