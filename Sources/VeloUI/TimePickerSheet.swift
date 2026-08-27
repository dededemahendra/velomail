import SwiftUI
import VeloCore

/// Asks for a date and time.
///
/// Presets first, because most of the time one of them is the answer and a
/// calendar is slower than a button. The picker is for the rest.
struct TimePickerSheet: View {
    let request: AppViewModel.TimeRequest
    let morningHour: Int
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var chosen: Date

    init(request: AppViewModel.TimeRequest, morningHour: Int,
         onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.request = request
        self.morningHour = morningHour
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        _chosen = State(initialValue: request.suggested)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(request.title)
                .font(.system(size: 15, weight: .semibold))
                .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 12)

            VStack(spacing: 6) {
                ForEach(presets, id: \.0) { label, moment in
                    Button {
                        onConfirm(moment)
                    } label: {
                        HStack {
                            Text(label).font(.system(size: 13))
                            Spacer()
                            Text(Self.when(moment))
                                .font(.system(size: 11).monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .contentShape(Rectangle())
                        .background(.quaternary.opacity(0.22),
                                    in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)

            Divider().padding(.vertical, 14)

            DatePicker("", selection: $chosen)
                .datePickerStyle(.field)
                .labelsHidden()
                .accessibilityLabel(request.title)
                .padding(.horizontal, 20)

            HStack {
                Spacer()
                Button("Cancel", action: onCancel).keyboardShortcut(.cancelAction)
                Button(request.title, action: { onConfirm(chosen) })
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20).padding(.vertical, 16)
        }
        .frame(width: 340)
        .onExitCommand(perform: onCancel)
    }

    /// The answers worth a single click. Later today only while there is a
    /// later today worth having.
    private var presets: [(String, Date)] {
        var options: [(String, Date)] = []
        let inThreeHours = Date().addingTimeInterval(3 * 3_600)
        if Calendar.current.isDateInToday(inThreeHours) {
            options.append(("Later today", inThreeHours))
        }
        options.append(("Tomorrow morning", Horizon.tomorrow(hour: morningHour)))
        options.append(("Next week", Horizon.nextWeek(hour: morningHour)))
        return options
    }

    static func when(_ moment: Date) -> String {
        let formatter = DateFormatter()
        formatter.doesRelativeDateFormatting = true
        formatter.dateStyle = Calendar.current.isDateInToday(moment) ? .none : .short
        formatter.timeStyle = .short
        return formatter.string(from: moment)
    }
}
