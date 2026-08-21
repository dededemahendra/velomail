import SwiftUI

public struct VeloMailApp: App {
    @StateObject private var host = AppHost()

    public init() {}

    public var body: some Scene {
        WindowGroup("Velo Mail") {
            RootView(app: host.app)
                    .task { await host.start() }
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}
