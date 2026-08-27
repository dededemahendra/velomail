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
        // The column is told to fill the pane, so the chart grows into the
        // space rather than floating above it. Inside a ScrollView an
        // unconstrained height means "as tall as the content", which for a
        // fixed dashboard is a small block and a lot of nothing.
        GeometryReader { proxy in
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
                    .frame(maxHeight: .infinity)
            }
            .frame(maxWidth: 620, alignment: .leading)
            .padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 34)
            .frame(maxWidth: .infinity, alignment: .center)
            .frame(minHeight: proxy.size.height - 1, alignment: .top)
        }
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
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                legend("Received", .accentColor)
                legend("Sent", .secondary)
                Spacer()
            }

            GeometryReader { proxy in
                let plot = max(proxy.size.height - 34, 40)
                ZStack(alignment: .bottomLeading) {
                    // A scale, because a bar with nothing to measure against
                    // says only "more than that one".
                    gridlines(peak: peak, height: plot)

                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                            VStack(spacing: 7) {
                                HStack(alignment: .bottom, spacing: 5) {
                                    bar(day.received, peak: peak, plot: plot, color: .accentColor)
                                    bar(day.sent, peak: peak, plot: plot, color: .secondary)
                                }
                                Text(Self.weekday(day.day))
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                            .frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(
                                "\(Self.weekday(day.day)), \(day.received) received, \(day.sent) sent")
                        }
                    }
                }
            }
            .frame(minHeight: 200)
        }
    }

    /// A line at nothing and a line at the busiest day, with the number on it.
    ///
    /// Two only: a chart of seven days does not need five, and every line drawn
    /// is one more thing between the reader and the shape.
    private func gridlines(peak: Int, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            VStack(spacing: 0) {
                HStack(spacing: 6) {
                    Text("\(peak)")
                        .font(.system(size: 9).monospacedDigit())
                        .foregroundStyle(.tertiary)
                    Rectangle().fill(.quaternary).frame(height: 1)
                }
                Spacer(minLength: 0)
                Rectangle().fill(.quaternary).frame(height: 1)
            }
            .frame(height: height)
        }
        .padding(.bottom, 24)
    }

    private func bar(_ value: Int, peak: Int, plot: CGFloat, color: Color) -> some View {
        VStack(spacing: 3) {
            // The number above the bar. Reading a height off a chart is
            // guessing; this is the answer the reader came for.
            Text(value > 0 ? "\(value)" : "")
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.tertiary)
            // A visible stub at zero, so an empty day reads as "none" rather
            // than as a missing bar.
            RoundedRectangle(cornerRadius: 3)
                .fill(color.opacity(value == 0 ? 0.18 : 0.85))
                .frame(width: 16, height: max(3, CGFloat(value) / CGFloat(peak) * (plot - 14)))
        }
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
