import Foundation
import VeloCore

/// Works out what each row in a thread actually has to say.
///
/// A thread of twelve deployment alerts repeats the sender twelve times and
/// the date twelve times, and the only thing that varies is the clock. Deciding
/// that here rather than in the view keeps it testable and keeps the rule in
/// one place.
enum TranscriptRows {
    struct Row: Equatable, Identifiable {
        let message: Message
        /// False when the message above is from the same person on the same
        /// day, so a run reads as one conversation rather than a list.
        let showsSender: Bool
        /// Set on the first message of each day, and nowhere else.
        let dayHeading: String?
        /// The clock only. The day is on the heading above.
        let time: String
        /// False when this row would repeat the line above word for word.
        /// Nine alerts that all say the same thing say it once.
        let showsPreview: Bool

        var id: String { message.id }
    }

    static func build(_ messages: [Message], now: Date = Date(),
                      calendar: Calendar = .current) -> [Row] {
        var rows: [Row] = []
        var previous: Message?

        for message in messages {
            let startsADay = previous.map {
                !calendar.isDate($0.date, inSameDayAs: message.date)
            } ?? true
            // A run restarts at a date heading: a row with no name under a
            // fresh heading reads as orphaned.
            let sameSender = previous?.sender == message.sender
            let namesSender = startsADay || !sameSender
            // A different voice always gets its words shown, even if by
            // coincidence they match: a row with only a time under a new name
            // says nothing at all.
            let repeatsItself = !namesSender && previous?.previewText == message.previewText
            rows.append(Row(message: message,
                            showsSender: namesSender,
                            dayHeading: startsADay
                                ? MailFormatting.dayHeading(message.date, now: now,
                                                            calendar: calendar)
                                : nil,
                            time: clock.string(from: message.date),
                            showsPreview: !repeatsItself))
            previous = message
        }
        return rows
    }

    private static let clock: DateFormatter = {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }()
}

private extension Message {
    /// What the collapsed row would show, for comparing one row against the
    /// one above it.
    var previewText: String {
        (bodyText ?? bodyHTML ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
