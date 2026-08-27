import SwiftUI
import VeloCore

/// Who is filling your inbox, and what to do about them.
///
/// A mailbox is a handful of senders sending a great deal and a long tail
/// sending once, and nothing here would tell you which. Triage had to be done a
/// thread at a time even when four hundred of them came from one address.
struct SendersView: View {
    let senders: [SenderSummary]
    /// Every thread in the inbox, for working out each sender's share.
    let totalThreads: Int
    let selected: Int?
    let onSelect: (Int) -> Void
    let onArchiveAll: (SenderSummary) -> Void
    let onAlwaysArchive: (SenderSummary) -> Void
    let onUnsubscribe: (SenderSummary) -> Void
    let onOpen: (SenderSummary) -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text("Senders").font(.headline)
                if !senders.isEmpty {
                    Text("\(senders.count) in \(totalThreads) threads")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose).keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 14)
            Divider()

            if senders.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "person.2").font(.system(size: 26))
                        .foregroundStyle(.tertiary)
                    Text("Nothing in the inbox").font(.system(size: 13, weight: .medium))
                    Text("This is the view for deciding who to stop hearing from.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(Array(senders.enumerated()), id: \.element.id) { index, sender in
                            row(sender, isSelected: index == selected)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(index) }
                        }
                    }
                    .padding(8)
                }
                .scrollIndicators(.hidden)
            }
        }
        .frame(width: 620, height: 480)
        .onExitCommand(perform: onClose)
    }

    private func row(_ sender: SenderSummary, isSelected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(sender.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if sender.unread > 0 {
                    Text("\(sender.unread) unread")
                        .font(.system(size: 10, weight: .medium))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(.tint.opacity(0.18), in: Capsule())
                }
                Spacer(minLength: 8)
                Text("\(sender.threads)")
                    .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text(percent(sender))
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .frame(width: 34, alignment: .trailing)
            }

            // The bar is the point of the screen: 41% from one address is a
            // fact you take in without reading a number.
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary.opacity(0.5))
                    Capsule().fill(.tint.opacity(0.65))
                        .frame(width: max(2, proxy.size.width * sender.share(of: totalThreads)))
                }
            }
            .frame(height: 4)

            if isSelected {
                HStack(spacing: 8) {
                    Button("Open") { onOpen(sender) }
                    Button("Archive all \(sender.threads)") { onArchiveAll(sender) }
                    Button("Always archive") { onAlwaysArchive(sender) }
                    if sender.canUnsubscribe {
                        Button("Unsubscribe") { onUnsubscribe(sender) }
                    }
                    Spacer()
                }
                .controlSize(.small)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background {
            if isSelected {
                RoundedRectangle(cornerRadius: 8).fill(.tint.opacity(0.12))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spoken(sender))
    }

    private func percent(_ sender: SenderSummary) -> String {
        let share = sender.share(of: totalThreads) * 100
        // No decimals: this is a sense of scale, not a measurement.
        return share < 1 ? "<1%" : "\(Int(share.rounded()))%"
    }

    private func spoken(_ sender: SenderSummary) -> String {
        var parts = ["\(sender.displayName), \(sender.threads) threads, \(percent(sender)) of the inbox"]
        if sender.unread > 0 { parts.append("\(sender.unread) unread") }
        if sender.canUnsubscribe { parts.append("can be unsubscribed from") }
        return parts.joined(separator: ", ")
    }
}
