import Foundation

/// Observed change in the local clock time of the main recorded sleep period
/// between adjacent wake dates. This is distinct from a sleep regularity index.
public struct SleepTimingVariation {
    public let observedDays: Int
    public let adjacentPairs: Int
    public let medianOnsetChange: Double?
    public let medianWakeChange: Double?

    public static func reportStart(endingAt end: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -7, to: calendar.startOfDay(for: end))!
    }

    public static func evaluate(_ samples: [SleepInterval], endingAt now: Date,
                                calendar: Calendar) -> Self {
        let end = calendar.startOfDay(for: now)
        let start = reportStart(endingAt: now, calendar: calendar)
        var mainByWakeDay: [Date: (start: Date, end: Date, asleepSeconds: TimeInterval)] = [:]
        var run: (start: Date, end: Date, asleepSeconds: TimeInterval)?

        func storeRun() {
            guard let run, run.end >= start, run.end < end else { return }
            let wakeDay = calendar.startOfDay(for: run.end)
            // Chronological traversal keeps the earlier run in an exact tie.
            if run.asleepSeconds > (mainByWakeDay[wakeDay]?.asleepSeconds ?? 0) {
                mainByWakeDay[wakeDay] = run
            }
        }
        for segment in SleepCalculator.segments(samples) where segment.stage != .awake {
            let length = segment.end.timeIntervalSince(segment.start)
            if let previous = run, segment.start.timeIntervalSince(previous.end) < 2 * 3600 {
                run = (previous.start, segment.end, previous.asleepSeconds + length)
            } else {
                storeRun()
                run = (segment.start, segment.end, length)
            }
        }
        storeRun()

        func clockChange(_ lhs: Date, _ rhs: Date) -> Double {
            func minutes(_ date: Date) -> Double {
                let parts = calendar.dateComponents([.hour, .minute, .second], from: date)
                return Double(parts.hour! * 60 + parts.minute!) + Double(parts.second!) / 60
            }
            let difference = abs(minutes(lhs) - minutes(rhs))
            return min(difference, 1440 - difference)
        }
        func median(_ values: [Double]) -> Double? {
            guard !values.isEmpty else { return nil }
            let sorted = values.sorted()
            return (sorted[(sorted.count - 1) / 2] + sorted[sorted.count / 2]) / 2
        }
        var onsets: [Double] = []
        var wakes: [Double] = []
        for (day, current) in mainByWakeDay {
            guard let yesterday = calendar.date(byAdding: .day, value: -1, to: day),
                  let previous = mainByWakeDay[yesterday] else { continue }
            onsets.append(clockChange(previous.start, current.start))
            wakes.append(clockChange(previous.end, current.end))
        }
        return Self(observedDays: mainByWakeDay.count, adjacentPairs: onsets.count,
                    medianOnsetChange: median(onsets), medianWakeChange: median(wakes))
    }
}
