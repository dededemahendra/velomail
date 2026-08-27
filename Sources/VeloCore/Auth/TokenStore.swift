import Foundation

/// Sendable because the read happens off the main actor: a Keychain read can
/// block on an authorisation prompt, and the window must be able to draw while
/// that prompt is on screen.
public protocol TokenStore: Sendable {
    func load() throws -> TokenSet?
    func save(_ tokenSet: TokenSet) throws
    func clear() throws
}

public final class InMemoryTokenStore: TokenStore, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: TokenSet?

    public init() {}

    public func load() throws -> TokenSet? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ tokenSet: TokenSet) throws {
        lock.lock(); defer { lock.unlock() }
        stored = tokenSet
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
