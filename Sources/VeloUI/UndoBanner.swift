import SwiftUI
import VeloCore

/// The undo-send strip. Present only while the window is open, which is what
/// makes the promise honest: once it goes, the mail is gone.
struct UndoBanner: View {
    let prompt: String
    var symbol: String = "arrow.uturn.backward"
    /// The whole window, start to finish, when there is one worth drawing.
    ///
    /// The interval and not just its end: a bar showing how much is left has to
    /// know how much there was. Written as `Date()...deadline` it read the
    /// clock inside `body`, so every recomputation started the interval again
    /// from the current moment and the bar snapped back to full -- which is
    /// most of the time while a run of threads is being archived.
    var interval: ClosedRange<Date>?
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.caption)
                .accessibilityHidden(true)
            Text(prompt).font(.callout)
            Spacer()
            // The shortcut is the way this is meant to be used; the button is
            // for the times the writer has already reached for the mouse.
            Text("\u{2318}Z").font(.caption2).foregroundStyle(.tertiary)
            if let interval, interval.upperBound > Date() {
                // A hairline rather than a number: it answers "how long have I
                // got" at a glance without asking to be read.
                //
                // Driven by a timeline over an explicit fraction rather than by
                // `ProgressView(timerInterval:)`. The timer form has to be told
                // an interval, and an interval is a value, so it restarts
                // whenever the value does -- which is every time this body runs.
                // A fraction computed from a fixed window and the current tick
                // cannot restart, and unlike the timer form it can be tested.
                TimelineView(.periodic(from: interval.lowerBound, by: 0.1)) { tick in
                    ProgressView(value: UndoBanner.fractionRemaining(at: tick.date, of: interval))
                        .progressViewStyle(.linear)
                        .frame(width: 46)
                        .tint(.secondary)
                }
                .accessibilityHidden(true)
            }
            Button("Undo", action: onUndo)
                .buttonStyle(.borderless)
                .keyboardShortcut("z", modifiers: .command)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .bannerWidth()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    /// How much of the window is left at `moment`, from 1 down to 0.
    ///
    /// Clamped at both ends: a tick can arrive after the deadline, and a window
    /// of no length at all would otherwise divide by zero.
    static func fractionRemaining(at moment: Date, of window: ClosedRange<Date>) -> Double {
        let span = window.upperBound.timeIntervalSince(window.lowerBound)
        guard span > 0 else { return 0 }
        let left = window.upperBound.timeIntervalSince(moment)
        return min(1, max(0, left / span))
    }
}

/// What the queue gave up on.
///
/// Deliberately unlike `UndoBanner`: no countdown and no automatic dismissal.
/// A message that never went is not a ten second offer, and the writer has to
/// be the one who decides it has been dealt with.
/// Says the sign-in has run out, and offers the one thing that fixes it.
///
/// Not dismissible, and above everything else: a mail client that has quietly
/// stopped syncing looks exactly like a mail client where nobody has written
/// to you. It sits over the list rather than in the empty state, because an
/// inbox with four hundred threads in it is never empty and would never have
/// shown one.
struct SignInAgainBanner: View {
    let onSignIn: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.caption).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 1) {
                Text("Sign-in expired").font(.callout.weight(.medium))
                Text("New mail has stopped arriving.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Button("Sign in", action: onSignIn).buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .bannerWidth()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Sign-in expired. New mail has stopped arriving.")
    }
}

struct FailureBanner: View {
    let prompt: String
    /// Present only when there is a draft to put back in the composer.
    let canReopen: Bool
    /// How many more are waiting behind this one.
    var overflow: Int = 0
    let onReopen: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
            Text(prompt).font(.callout).lineLimit(1)
            if overflow > 0 {
                Text("+\(overflow) more").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            if canReopen {
                Button("Reopen", action: onReopen).buttonStyle(.borderless)
            }
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(prompt)
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(.orange.opacity(0.45), lineWidth: 1))
        .bannerWidth()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// A plain answer to something the writer just asked for.
///
/// No action and no countdown of its own: it says what happened and gets out
/// of the way when the next thing does.
struct NoticeBanner: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Text(text).font(.callout)
        }
        .padding(.horizontal, 16).padding(.vertical, 9)
        .floatingSurface()
        .bannerWidth()
        .padding(.horizontal, 16).padding(.bottom, 12)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

/// Threads you are waiting on, shown by `g f`.
struct FollowUpBar: View {
    let threads: [MailThread]
    let onDismiss: () -> Void
    let onOpen: (MailThread) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "clock.arrow.circlepath").font(.caption)
                Text("AWAITING REPLY").font(.caption.weight(.semibold))
                Spacer()
                Button { onDismiss() } label: { Image(systemName: "xmark").font(.caption) }
                    .buttonStyle(.plain)
            }
            .foregroundStyle(.secondary)

            if threads.isEmpty {
                Text("Nothing is waiting on a reply.")
                    .font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(threads) { thread in
                    Button { onOpen(thread) } label: {
                        HStack {
                            Text(HTMLText.preview(thread.snippet))
                                .font(.callout).lineLimit(1)
                            Spacer()
                            Text(MailFormatting.relativeDate(thread.lastMessageDate))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.horizontal, 24).padding(.vertical, 12)
        .background(.quaternary.opacity(0.35))
    }
}
