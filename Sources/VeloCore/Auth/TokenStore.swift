import Foundation

public protocol TokenStore {
    func load() throws -> TokenSet?
    func save(_ tokenSet: TokenSet) throws
    func clear() throws
}

public final class InMemoryTokenStore: TokenStore {
    private var stored: TokenSet?

    public init() {}

    public func load() throws -> TokenSet? { stored }
    public func save(_ tokenSet: TokenSet) throws { stored = tokenSet }
    public func clear() throws { stored = nil }
}
