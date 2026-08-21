import SwiftUI

/// Routes to whichever surface the app state says is focused.
public struct RootView: View {
    @ObservedObject var app: AppViewModel

    public init(app: AppViewModel) { self.app = app }

    public var body: some View {
        Group {
            switch app.route {
            case .setup:
                SetupView(clientIDHint: app.setupHint)
            case .list, .thread, .compose, .palette:
                Text("inbox")
            }
        }
    }
}
