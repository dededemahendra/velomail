import SwiftUI

/// Shown when no OAuth client id is configured. A mail client that dies because
/// it has no credentials is worse than one that explains itself.
///
/// It used to explain itself in a single paragraph with bullets inside it,
/// which is the shape text takes when nobody has decided what the reader is
/// meant to *do*. It is a numbered list now, with the exact strings to copy and
/// a way out for someone who would rather look around first.
struct SetupView: View {
    var steps: [SetupStep] = Setup.steps

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hasAppeared = false
    @State private var copied: Int?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .modifier(Arrival(step: 0, active: hasAppeared, reduced: reduceMotion))

                ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
                    StepRow(step: step,
                            isCopied: copied == step.number,
                            onCopy: { copy(step) })
                        .modifier(Arrival(step: index + 1, active: hasAppeared,
                                          reduced: reduceMotion))
                }

                demo
                    .modifier(Arrival(step: steps.count + 1, active: hasAppeared,
                                      reduced: reduceMotion))
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 44)
            .padding(.vertical, 40)
            .frame(maxWidth: .infinity)
        }
        .onAppear { hasAppeared = true }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            VeloMarkView(side: 60)
                .padding(.bottom, 6)
            Text("Connect a Google account")
                .font(.system(size: 28, weight: .semibold))
                .tracking(-0.4)
            Text("Velo Mail talks to Gmail directly, with credentials you own. "
                 + "Four steps, once.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.bottom, 28)
    }

    private var demo: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().padding(.vertical, 18)
            Text("Or look around first")
                .font(.callout.weight(.medium))
            Text("Demo mode seeds a mailbox in memory. Nothing touches the "
                 + "network and nothing is kept.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            SnippetBlock(text: Setup.demoHint, isCopied: copied == -1) {
                copy(text: Setup.demoHint, token: -1)
            }
        }
    }

    private func copy(_ step: SetupStep) {
        guard let snippet = step.snippet else { return }
        copy(text: snippet, token: step.number)
    }

    private func copy(text: String, token: Int) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // Says it happened, then stops saying it. A tick that never leaves
        // stops meaning "just now".
        withAnimation(.spring(response: 0.3, dampingFraction: 1)) { copied = token }
        Task {
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.2)) { if copied == token { copied = nil } }
        }
    }
}

private struct StepRow: View {
    let step: SetupStep
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(step.number)")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 6) {
                Text(step.title).font(.body.weight(.medium))
                Text(step.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let link = step.link {
                    Link(destination: link) {
                        Label(link.host ?? link.absoluteString, systemImage: "arrow.up.right")
                            .font(.callout)
                    }
                    .padding(.top, 2)
                }
                if let snippet = step.snippet {
                    SnippetBlock(text: snippet, isCopied: isCopied, onCopy: onCopy)
                        .padding(.top, 4)
                }
            }
        }
        .padding(.bottom, 22)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Step \(step.number). \(step.title). \(step.detail)")
    }
}

/// Something to copy, that says so and copies itself.
private struct SnippetBlock: View {
    let text: String
    let isCopied: Bool
    let onCopy: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(text)
                .font(.system(size: 11.5, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onCopy) {
                // Swapped rather than relabelled, so the change is a change of
                // state and not a flicker of text.
                Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                    .font(.caption)
                    .foregroundStyle(isCopied ? Color.green : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isCopied ? "Copied" : "Copy")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.quaternary, lineWidth: 1))
    }
}

/// Lifts one element into place, a beat after the one above it.
private struct Arrival: ViewModifier {
    let step: Int
    let active: Bool
    let reduced: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 1 : 0)
            .offset(y: reduced || active ? 0 : 12)
            .animation(reduced
                       ? .easeOut(duration: 0.22)
                       : .spring(response: 0.5, dampingFraction: 1)
                           .delay(Double(step) * 0.06),
                       value: active)
    }
}
