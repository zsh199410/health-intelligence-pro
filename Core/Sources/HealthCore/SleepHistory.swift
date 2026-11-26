import Foundation

/// One calendar day of sleep, grouped by wake date (the day the sleep ended),
/// matching the convention of `SleepTimingVariation`.
public struct SleepHistoryDay: Identifiable, Equatable, Sendable {
    public var id: Date { date }
    /// Start of the calendar day on which the sleep ended.
    public let date: Date
    public let asleepMinutes: Int
    public var hasRecord: Bool { asleepMinutes > 0 }

    public init(date: Date, asleepMinutes: Int) {
        self.date = date
        self.asleepMinutes = asleepMinutes
    }
}

/// Daily sleep totals for the past `days` calendar days ending today.
/// Built on `SleepCalculator.segments`, so overlapping sources are
/// deduplicated with the same stage precedence as the latest-night summary.
/// Asleep stages are deep / REM / core / unspecified; awake minutes never
/// count as sleep. Segments are clipped to the requested window and to
/// `endingAt`, so future-dated samples contribute nothing. A day with no
/// asleep segment is reported with 0 minutes and `hasRecord == false`:
/// missing data is never shown as a night of zero sleep, and no value is
/// interpolated across missing days.
public enum SleepHistory {
    public static func days(from intervals: [SleepInterval], days: Int = 7,
                            endingAt now: Date = Date(),
                            calendar: Calendar = .current) -> [SleepHistoryDay] {
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: now)
        guard let windowStart = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return [] }
        var totals: [Date: Int] = [:]
        for segment in SleepCalculator.segments(intervals) {
            guard segment.stage != .awake else { continue }
            let start = max(segment.start, windowStart)
            let end = min(segment.end, now)
            guard end > start else { continue }
            let minutes = Int((end.timeIntervalSince(start) / 60).rounded())
            guard minutes > 0 else { continue }
            let day = calendar.startOfDay(for: end)
            totals[day, default: 0] += minutes
        }
        return (0..<days).compactMap { offset in
            calendar.date(byAdding: .day, value: offset, to: windowStart)
                .map { SleepHistoryDay(date: $0, asleepMinutes: totals[$0] ?? 0) }
        }
    }
}
