import Foundation

/// What "later" means, for a snooze or a send.
///
/// Wake times land on a round hour of the working day rather than the exact
/// moment plus an offset. A thread snoozed at 16:47 coming back at 09:00 is
/// useful; coming back at 16:47 the next day is the same interruption moved.
public enum Horizon {
    // Shared by snooze and send-later on purpose: "tomorrow morning" should
    // mean the same hour whichever of the two the writer picked.

    /// The next morning, at `hour`.
    public static func tomorrow(now: Date = Date(), hour: Int = 9,
                                calendar: Calendar = .current) -> Date {
        nextOccurrence(ofHour: hour, daysAhead: 1, now: now, calendar: calendar)
    }

    /// The morning of the coming week.
    public static func nextWeek(now: Date = Date(), hour: Int = 9,
                                calendar: Calendar = .current) -> Date {
        nextOccurrence(ofHour: hour, daysAhead: 7, now: now, calendar: calendar)
    }

    private static func nextOccurrence(ofHour hour: Int, daysAhead: Int, now: Date,
                                       calendar: Calendar) -> Date {
        let day = calendar.date(byAdding: .day, value: daysAhead, to: now) ?? now
        var parts = calendar.dateComponents([.year, .month, .day], from: day)
        parts.hour = hour
        parts.minute = 0
        // A calendar can refuse a time that does not exist locally (the hour a
        // clock change skips). Falling back keeps the snooze rather than losing it.
        return calendar.date(from: parts) ?? day
    }
}
