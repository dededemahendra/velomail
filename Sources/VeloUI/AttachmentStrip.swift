import SwiftUI
import VeloCore

/// The files on a message, as chips under its header.
struct AttachmentStrip: View {
    let attachments: [MailAttachment]
    @ObservedObject var model: AttachmentViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FlowRow(spacing: 8) {
                ForEach(attachments) { attachment in
                    chip(attachment)
                }
            }
            status
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 10)
    }

    private func chip(_ attachment: MailAttachment) -> some View {
        Button {
            Task { await model.save(attachment) }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: AttachmentViewModel.symbol(for: attachment.mimeType))
                    .font(.caption)
                Text(attachment.filename).font(.caption).lineLimit(1)
                let size = AttachmentViewModel.formattedSize(attachment.size)
                if !size.isEmpty {
                    Text(size).font(.caption2).foregroundStyle(.secondary)
                }
                Image(systemName: "arrow.down.circle").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Save \(attachment.filename) to Downloads")
    }

    @ViewBuilder
    private var status: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case let .saving(name):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Saving \(name)…").font(.caption).foregroundStyle(.secondary)
            }
        case let .saved(url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").font(.caption).foregroundStyle(.green)
                Text("Saved to \(url.deletingLastPathComponent().lastPathComponent)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Show") { model.reveal(url) }
                    .buttonStyle(.borderless).font(.caption)
            }
        case let .failed(message):
            Text(message).font(.caption).foregroundStyle(.orange)
        }
    }
}

/// Wraps chips onto as many lines as they need.
///
/// A plain `HStack` would push a long filename off the edge, and a `ScrollView`
/// would hide files behind a scroll nobody looks for.
struct FlowRow: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var rowWidth: CGFloat = 0, totalHeight: CGFloat = 0, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if rowWidth > 0, rowWidth + spacing + size.width > width {
                totalHeight += rowHeight + spacing
                rowWidth = size.width
                rowHeight = size.height
            } else {
                rowWidth += rowWidth > 0 ? spacing + size.width : size.width
                rowHeight = max(rowHeight, size.height)
            }
        }
        return CGSize(width: width == .infinity ? rowWidth : width, height: totalHeight + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize,
                       subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
