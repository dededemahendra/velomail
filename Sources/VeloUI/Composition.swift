import Foundation
import VeloCore

/// The composition root: opens the store, wires the engine, and hands back a
/// ready `AppViewModel`. Kept out of the view models so they stay testable
/// against an in-memory database.
public enum Composition {
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
    public static func make(config: AppConfig = .resolve(),
                            llm: LLMConfig = .resolve(),
                            snippets: SnippetLibrary = .resolve()) throws -> Assembly {
        // Demo runs in memory: it exists to be looked at, not to persist.
        let database = config.isDemo
            ? try AppDatabase.makeInMemory()
            : try AppDatabase.make(atPath: databaseURL.path)

        let store = MailStore(database)
        let mutations = MutationStore(database)
        let syncState = SyncStateStore(database)
        let drafts = DraftStore(database)
        let ruleLibrary = RuleLibrary.load()
        // The account id is stable and local; the *address* is discovered from
        // Gmail's profile on first backfill. Keeping them separate is what lets
        // the app be built before it knows who it is.
        let accountID = "primary"
        let configuredIdentity = ProcessInfo.processInfo.environment[identityKey]
        let resolver = IdentityResolver(syncState: syncState, accountID: accountID,
                                        configured: configuredIdentity)

        if config.isDemo { try DemoData.seed(into: store) }

        // AI is entirely optional: with nothing configured the provider is nil
        // and the app is exactly what it was before AI existed.
        let assistant = MailAssistant(provider: llm.makeProvider(httpClient: URLSessionHTTPClient(session: LLMConfig.makeHTTPClientSession())))

        // Demo takes the local path even when credentials exist. Once a config
        // file is present every launch has a clientID, and without this check
        // the flag silently stops meaning anything -- while the app quietly
        // signs in to a real account.
        guard let clientID = config.clientID, !config.isDemo else {
            // Unconfigured: still a fully working local app, just with nothing
            // to sync. A local-only writer keeps the queue honest.
            let outbound = OutboundService(writer: LocalOnlyWriter(), store: store,
                                           mutations: mutations, identity: resolver.identity)
            return Assembly(app: AppViewModel(config: config, store: store,
                                              outbound: outbound, identity: resolver.identity,
                                              assistant: assistant, snippets: snippets,
                                              drafts: drafts),
                            sync: nil, store: store, auth: nil)
        }

        let httpClient = URLSessionHTTPClient()
        // The redirect is derived from the client id; see AuthConfig.
        let authConfig = AuthConfig.gmail(clientID: clientID, clientSecret: config.clientSecret)
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
            syncState: syncState,
            // Rules see arrivals only; GmailSync never hands it a backfill.
            rules: RuleApplier(engine: RuleEngine(rules: ruleLibrary.rules),
                               store: store, outbound: outbound))

        let auth = AuthCoordinator(config: authConfig, tokenService: tokenService, tokenStore: tokenStore)
        let app = AppViewModel(config: config, store: store, outbound: outbound,
                               // Signed-in state is restored after launch, not during it.
                               identity: resolver.identity, isSignedIn: false,
                               assistant: assistant, snippets: snippets,
                               attachmentModel: AttachmentViewModel(
                                   service: AttachmentService(source: api)),
                               drafts: drafts)
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
