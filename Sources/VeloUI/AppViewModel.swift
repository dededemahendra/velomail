import SwiftUI

public enum Route: Equatable, Sendable {
    case setup, list, thread, compose, palette
}

@MainActor
public final class AppViewModel: ObservableObject {
    @Published public private(set) var route: Route = .setup
    public var setupHint: String { AppConfig.setupInstructions }

    public static func live() -> AppViewModel { AppViewModel() }
}
