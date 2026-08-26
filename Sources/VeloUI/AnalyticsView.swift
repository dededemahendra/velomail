import SwiftUI
import VeloCore

/// How mail has actually flowed this week.
///
/// A dashboard is scanned, not read, so the summary comes before the detail and
/// the chart carries the shape while the tiles carry the numbers.
struct AnalyticsView: View {
    let report: MailAnalytics.Report?
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if let report, report.received + report.sent > 0 {
                content(report)
            } else {
                empty
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand(perform: onClose)
    }

    private var header: some View {
        HStack {
            Text("Last 7 days")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button("Close", action: onClose).buttonStyle(.borderless).font(.caption)
        }
        .padding(.horizontal, 24).padding(.vertical, 14)
    }

    private func content(_ report: MailAnalytics.Report) -> some View {
        ScrollView {
            // A measured column rather than the full window width: four numbers
            // and a week of bars stretched across a wide display read as a page
            // that failed to load.
            VStack(alignment: .leading, spacing: 30) {
                HStack(alignment: .top, spacing: 0) {
                    tile("Received", "\(report.received)")
                    Spacer(minLength: 20)
                    tile("Sent", "\(report.sent)")
                    Spacer(minLength: 20)
                    tile("Median reply", Self.duration(report.medianResponse))
                    Spacer(minLength: 20)
                    tile("Busiest hour", Self.hour(report.busiestHour))
                }
                Divider()
                chart(report.daily)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 40)
            .frame(maxWidth: .infinity, alignment: .center)
        }
    }

    private func tile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value)
                .font(.system(size: 28, weight: .semibold))
                .monospacedDigit()
            Text(label.uppercased())
                .font(.system(size: 10, weight: .medium))
                .tracking(0.8)
                .foregroundStyle(.tertiary)
        }
    }

    /// Received and sent per day. Bars rather than a line: these are counts of
    /// discrete things, and a line between them would imply values in between.
    private func chart(_ days: [MailAnalytics.Day]) -> some View {
        let peak = max(days.map { max($0.received, $0.sent) }.max() ?? 1, 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                legend("Received", .accentColor)
                legend("Sent", .secondary)
            }
            HStack(alignment: .bottom, spacing: 0) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    VStack(spacing: 8) {
                        HStack(alignment: .bottom, spacing: 4) {
                            bar(day.received, peak: peak, color: .accentColor)
                            bar(day.sent, peak: peak, color: .secondary)
                        }
                        Text(Self.weekday(day.day))
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 190, alignment: .bottom)
        }
    }

    private func bar(_ value: Int, peak: Int, color: Color) -> some View {
        // A visible stub at zero, so an empty day reads as "none" rather than
        // as a missing bar.
        RoundedRectangle(cornerRadius: 2)
            .fill(color.opacity(value == 0 ? 0.18 : 0.85))
            .frame(width: 13, height: max(3, CGFloat(value) / CGFloat(peak) * 150))
    }

    private func legend(_ label: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 2).fill(color.opacity(0.85)).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var empty: some View {
        VStack(spacing: 7) {
            Image(systemName: "chart.bar").font(.system(size: 22)).foregroundStyle(.tertiary)
            Text("Nothing to measure yet").font(.system(size: 13, weight: .medium))
            Text("Numbers appear once mail has been synced.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Formatting

    static func duration(_ seconds: TimeInterval?) -> String {
        guard let seconds else { return "—" }
        if seconds < 3600 { return "\(Int((seconds / 60).rounded()))m" }
        if seconds < 86_400 { return "\(Int((seconds / 3600).rounded()))h" }
        return "\(Int((seconds / 86_400).rounded()))d"
    }

    static func hour(_ hour: Int?) -> String {
        guard let hour else { return "—" }
        return String(format: "%02d:00", hour)
    }

    static func weekday(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter.string(from: date)
    }
}
