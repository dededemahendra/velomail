import SwiftUI

/// Shown when no OAuth client id is configured. A mail client that dies because
/// it has no credentials is worse than one that explains itself.
struct SetupView: View {
    let clientIDHint: String

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connect a Google account")
                .font(.title2.weight(.semibold))
            Text(clientIDHint)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
