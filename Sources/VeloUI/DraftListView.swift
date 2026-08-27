import SwiftUI
import VeloCore

/// The messages being written but not yet sent.
///
/// A list rather than a single resume prompt, because there is more than one
/// draft now: without somewhere to see them, the second and third would be
/// saved faithfully and reachable by nothing.
struct DraftListView: View {
    let drafts: [StoredDraft]
    /// Messages finished and waiting for their hour. They live here rather than
    /// on a screen of their own: both are mail not yet gone, and this is where
    /// a writer looks for unfinished business.
    var scheduled: [ScheduledSend] = []
    let onOpen: (StoredDraft) -> Void
    let onDiscard: (StoredDraft) -> Void
    var onSendNow: (ScheduledSend) -> Void = { _ in }
    var onUnschedule: (ScheduledSend) -> Void = { _ in }
    let onClose: () -> Void

    /// Everything listed, not just the drafts section: the count labels the
    /// screen, and "1" over three visible rows reads as a bug rather than a
    /// distinction.
    var headerCount: Int { drafts.count + scheduled.count }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Drafts").font(.system(size: 13, weight: .semibold))
                Text("\(headerCount)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16).padding(.vertical, 9)
            Divider()

            if drafts.isEmpty && scheduled.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        if !scheduled.isEmpty {
                            sectionHeader("Waiting to send")
                            ForEach(scheduled) { send in
                                scheduledRow(send)
                                Divider()
                            }
                        }
                        if !drafts.isEmpty {
                            if !scheduled.isEmpty { sectionHeader("Drafts") }
                            ForEach(drafts) { stored in
                                row(stored)
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func sectionHeader(_ title: String) -> some View {
        HStack {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 12).padding(.bottom, 5)
    }

    /// A message that is going, unless the writer stops it.
    private func scheduledRow(_ send: ScheduledSend) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "clock").font(.caption2).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(Self.recipients(of: send.draft))
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                Text(Self.summary(of: send.draft))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(MailFormatting.wakeTime(send.dueAt))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)

            Button("Send now") { onSendNow(send) }
                .buttonStyle(.borderless).font(.caption)
            Button("Edit") { onUnschedule(send) }
                .buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private func row(_ stored: StoredDraft) -> some View {
        HStack(spacing: 12) {
            Button {
                onOpen(stored)
            } label: {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Self.recipients(of: stored.draft))
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    Text(Self.summary(of: stored.draft))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Text(MailFormatting.relativeDate(stored.updatedAt))
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.tertiary)

            Button {
                onDiscard(stored)
            } label: {
                Image(systemName: "trash").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Discard this draft")
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Nothing half-written").font(.title3.weight(.medium))
            Text("Messages you leave unfinished wait here.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Who it is going to, or an honest admission that nobody is named yet.
    static func recipients(of draft: Draft) -> String {
        let named = draft.to.map(MailFormatting.displayName).filter { !$0.isEmpty }
        guard let first = named.first else { return "No recipient" }
        guard named.count > 1 else { return first }
        return "\(first) and \(named.count - 1) other\(named.count == 2 ? "" : "s")"
    }

    /// The subject, falling back to the opening words: a draft with no subject
    /// is still recognisable by what it says.
    static func summary(of draft: Draft) -> String {
        if !draft.subject.isEmpty { return draft.subject }
        let opening = draft.bodyText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
        return opening.isEmpty ? "No subject" : String(opening.prefix(80))
    }
}
