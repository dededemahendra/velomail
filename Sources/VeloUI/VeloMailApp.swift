import SwiftUI

public struct VeloMailApp: App {
    @StateObject private var host = AppHost()

    public init() {}

    public var body: some Scene {
        WindowGroup("Velo Mail") {
            // Keyed on the account so switching rebuilds the tree rather than
            // handing the old views a different view model underneath them.
            RootView(app: host.app)
                .id(host.currentAccountID)
                .task { await host.start() }
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}
