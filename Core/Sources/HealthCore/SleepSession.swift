import Foundation

/// Groups sleep intervals by gaps between the end of one session and the next sample.
public enum SleepSession {
    public static func window(from intervals: [SleepInterval], maxGap: TimeInterval = 2 * 3600) -> ClosedRange<Date>? {
        latest(from: intervals, maxGap: maxGap)?.window
    }

    /// Returns the most recent session's samples and full time range.
    public static func latest(
        from intervals: [SleepInterval],
        maxGap: TimeInterval = 2 * 3600
    ) -> (intervals: [SleepInterval], window: ClosedRange<Date>)? {
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard let first = sorted.first else { return nil }
        var sessionStart = 0
        var sessionEnd = first.end

        for index in sorted.indices.dropFirst() {
            let interval = sorted[index]
            if interval.start > sessionEnd && interval.start.timeIntervalSince(sessionEnd) >= maxGap {
                sessionStart = index
                sessionEnd = interval.end
            } else {
                sessionEnd = max(sessionEnd, interval.end)
            }
        }

        return (Array(sorted[sessionStart...]), sorted[sessionStart].start...sessionEnd)
    }
}
