import SwiftUI

struct SignInView: View {
    let state: AuthCoordinator.AuthState
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Text("Velo Mail").font(.largeTitle.weight(.semibold))
            Text("Sign in to your Google account to load your mail.")
                .foregroundStyle(.secondary)

            Button(action: onSignIn) {
                Text(isBusy ? "Waiting for Google…" : "Sign in with Google")
                    .frame(width: 200)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .disabled(isBusy)

            if case let .failed(reason) = state {
                Text(reason)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 380)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var isBusy: Bool { state == .signingIn }
}
