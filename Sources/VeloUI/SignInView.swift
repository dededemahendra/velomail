import SwiftUI

struct SignInView: View {
    let state: AuthCoordinator.AuthState
    let onSignIn: () -> Void

    /// Reduced motion means a gentler equivalent, not none: the screen still
    /// arrives, it simply does not travel to get here.
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VeloMarkView(side: 92)
                .shadow(color: .black.opacity(0.35), radius: 22, y: 8)
                .padding(.bottom, 30)
                .modifier(Arrival(step: 0, active: hasAppeared, reduced: reduceMotion))

            // Tighter tracking as the type grows: at this size the default
            // spacing reads as gappy.
            Text("Velo Mail")
                .font(.system(size: 34, weight: .semibold))
                .tracking(-0.6)
                .modifier(Arrival(step: 1, active: hasAppeared, reduced: reduceMotion))

            Text("Keyboard-first mail. Sign in with Google to load your inbox.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
                .padding(.top, 8)
                .modifier(Arrival(step: 2, active: hasAppeared, reduced: reduceMotion))

            signInButton
                .padding(.top, 28)
                .modifier(Arrival(step: 3, active: hasAppeared, reduced: reduceMotion))

            // Reserved rather than inserted, so the button does not jump up the
            // screen the moment something goes wrong.
            failure
                .frame(height: 58, alignment: .top)
                .padding(.top, 14)

            Spacer(minLength: 0)

            Text("Velo Mail talks to Gmail directly. Nothing goes anywhere else.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 26)
                .modifier(Arrival(step: 4, active: hasAppeared, reduced: reduceMotion))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear { hasAppeared = true }
    }

    private var signInButton: some View {
        Button(action: onSignIn) {
            HStack(spacing: 9) {
                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                }
                Text(isBusy ? "Waiting for Google…" : "Sign in with Google")
            }
            .frame(width: 210)
            .padding(.vertical, 3)
        }
        .controlSize(.large)
        .buttonStyle(.borderedProminent)
        .disabled(isBusy)
        // The one thing on the screen worth pressing, so Return presses it.
        .keyboardShortcut(.defaultAction)
        .animation(.spring(response: 0.32, dampingFraction: 1), value: isBusy)
    }

    @ViewBuilder
    private var failure: some View {
        if case let .failed(reason) = state {
            VStack(spacing: 6) {
                Label(reason, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.orange)
                    .multilineTextAlignment(.center)
                Text("Nothing was changed. Try again when you are ready.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 380)
            // Arrives with the same character as everything else, and from
            // below, which is where it sits.
            .transition(.opacity.combined(with: .move(edge: .bottom)))
        }
    }

    private var isBusy: Bool { state == .signingIn }
}

/// Lifts one element into place, a beat after the one above it.
///
/// A spring rather than a curve, critically damped: nothing here was thrown, so
/// nothing should overshoot. The stagger is what makes the screen read as
/// assembling rather than as five things appearing at once.
private struct Arrival: ViewModifier {
    let step: Int
    let active: Bool
    let reduced: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: reduced || active ? 0 : 14)
            .blur(radius: reduced || active ? 0 : 6)
            .animation(reduced
                       ? .easeOut(duration: 0.22)
                       : .spring(response: 0.55, dampingFraction: 1)
                           .delay(Double(step) * 0.07),
                       value: active)
    }
}
