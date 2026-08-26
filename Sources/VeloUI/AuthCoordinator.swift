import Foundation
import AuthenticationServices
import VeloCore

/// Drives the interactive OAuth leg: opens Google's consent page in
/// `ASWebAuthenticationSession`, validates the callback, and exchanges the code
/// for tokens through the existing `TokenService`.
///
/// Only the browser hop lives here. PKCE, the URL, the exchange and Keychain
/// storage are all VeloCore's and already tested; this is the part that needs a
/// window and therefore cannot be.
@MainActor
public final class AuthCoordinator: NSObject, ObservableObject {
    public enum AuthState: Equatable {
        case signedOut
        case signingIn
        case signedIn
        case failed(String)
    }

    @Published public private(set) var state: AuthState = .signedOut {
        didSet { if state != oldValue { onStateChange?(state) } }
    }

    /// Called on every transition. A callback rather than the host polling
    /// `state`: sign-in changes a handful of times in a session, so a timer
    /// would be pure waste.
    public var onStateChange: ((AuthState) -> Void)?

    private let config: AuthConfig
    private let tokenService: TokenService
    private let tokenStore: TokenStore
    private var session: ASWebAuthenticationSession?

    public init(config: AuthConfig, tokenService: TokenService, tokenStore: TokenStore) {
        self.config = config
        self.tokenService = tokenService
        self.tokenStore = tokenStore
        super.init()
    }

    /// Looks for a session left by a previous run.
    ///
    /// Deliberately *not* in `init`. A Keychain read can block on an
    /// authorisation prompt -- and does whenever the app's code signature
    /// changes, which an ad-hoc signed build does on every rebuild. Doing it
    /// during construction blocks the main thread before SwiftUI has created a
    /// window, so the app launches and shows nothing at all, with no error.
    public func restoreState() {
        guard ((try? tokenStore.load()) ?? nil) != nil else { return }
        state = .signedIn
    }

    public func signIn() {
        guard state != .signingIn else { return }
        state = .signingIn

        let pkce = PKCE.generate()
        let url = AuthURLBuilder.url(config: config, pkce: pkce)
        guard let scheme = URL(string: config.redirectURI)?.scheme else {
            state = .failed("Malformed redirect URI")
            return
        }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self else { return }
            Task { @MainActor in
                if let error {
                    // A user closing the window is a cancellation, not a failure
                    // worth shouting about.
                    let cancelled = (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin
                    self.state = cancelled ? .signedOut : .failed(error.localizedDescription)
                    return
                }
                await self.complete(callback: callback, pkce: pkce)
            }
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        self.session = session
        session.start()
    }

    public func signOut() {
        try? tokenStore.clear()
        state = .signedOut
    }

    // MARK: - Internals

    private func complete(callback: URL?, pkce: PKCE) async {
        guard let callback,
              let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems else {
            state = .failed("No authorization response")
            return
        }
        func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

        // The state check is what stops a forged callback being accepted.
        guard value("state") == pkce.state else {
            state = .failed("Authorization state mismatch")
            return
        }
        guard let code = value("code") else {
            state = .failed(value("error") ?? "Authorization denied")
            return
        }

        do {
            let tokens = try await tokenService.exchange(code: code, verifier: pkce.codeVerifier)
            try tokenStore.save(tokens)
            state = .signedIn
        } catch {
            state = .failed(String(describing: error))
        }
    }
}

extension AuthCoordinator: ASWebAuthenticationPresentationContextProviding {
    public func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApplication.shared.keyWindow ?? ASPresentationAnchor()
    }
}
