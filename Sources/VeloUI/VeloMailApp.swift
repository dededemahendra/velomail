import SwiftUI

public struct VeloMailApp: App {
    @StateObject private var app = AppViewModel.live()

    public init() {}

    public var body: some Scene {
        WindowGroup("Velo Mail") {
            RootView(app: app)
                .frame(minWidth: 900, minHeight: 560)
        }
        .windowToolbarStyle(.unified)
    }
}
