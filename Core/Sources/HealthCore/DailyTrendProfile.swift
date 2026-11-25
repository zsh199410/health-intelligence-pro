import Foundation

/// Inputs are HealthKit daily sums or means, already aggregated across sources.
public struct DailyTrendProfile {
    public let end: Date
    public let calendar: Calendar
    private let values: [Date: Double]

    public init(points: [TrendPoint], end: Date, calendar: Calendar = .current) {
        self.end = end
        self.calendar = calendar
        // Repeated buckets (e.g. an updated daily estimate) replace the old value.
        var values = [Date: Double]()
        for point in points where point.recordedAt <= end && point.value.isFinite {
            values[calendar.startOfDay(for: point.recordedAt)] = point.value
        }
        self.values = values
    }

    public func runs(days: Int) -> [[TrendPoint]] {
        var result: [[TrendPoint]] = []
        var run: [TrendPoint] = []
        guard days > 0 else { return [] }
        let today = calendar.startOfDay(for: end)
        for offset in (1 - days)...0 {
            guard let date = calendar.date(byAdding: .day, value: offset, to: today),
                  let value = values[date] else {
                if !run.isEmpty { result.append(run); run = [] }
                continue
            }
            run.append(TrendPoint(recordedAt: date, value: value))
        }
        if !run.isEmpty { result.append(run) }
        return result
    }

    /// Compare the most recent *complete calendar day* against the preceding
    /// 30 complete days. The median and interquartile range are descriptive.
    public var baseline: (count: Int, median: Double?, middleHalf: ClosedRange<Double>?, yesterday: Double?) {
        let today = calendar.startOfDay(for: end)
        let history = (-31 ... -2).compactMap { offset -> Double? in
            calendar.date(byAdding: .day, value: offset, to: today).flatMap { values[$0] }
        }.sorted()
        let previous = calendar.date(byAdding: .day, value: -1, to: today).flatMap { values[$0] }
        guard history.count >= 7 else { return (history.count, nil, nil, previous) }
        func quantile(_ fraction: Double) -> Double {
            let position = fraction * Double(history.count - 1)
            let low = Int(position)
            let high = Int(ceil(position))
            return history[low] + (history[high] - history[low]) * (position - Double(low))
        }
        return (history.count, quantile(0.5), quantile(0.25)...quantile(0.75), previous)
    }

    /// Two windows must contain the same elapsed duration since local midnight.
    /// DST can make yesterday too short to match today.
    public static func previousCutoff(end: Date, calendar: Calendar) -> Date? {
        let today = calendar.startOfDay(for: end)
        let duration = end.timeIntervalSince(today)
        guard duration > 0,
              let previous = calendar.date(byAdding: .day, value: -1, to: today) else { return nil }
        let cutoff = previous.addingTimeInterval(duration)
        return cutoff < today ? cutoff : nil
    }
}
