import Foundation

/// Local calendar days, including the partial day ending at the report cutoff.
public enum ReportPeriod: Int, CaseIterable, Sendable {
    case day = 1, week = 7, month = 30

    public func window(endingAt end: Date, calendar: Calendar = .current) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: end)
        let first = calendar.date(byAdding: .day, value: 1 - rawValue, to: today) ?? today
        return first...end
    }

    /// Input consists of one HealthKit daily sum or mean per local day.
    /// Days without a bucket contribute neither to the numerator nor the divisor.
    public func summarize(_ points: [TrendPoint], endingAt end: Date, cumulative: Bool,
                          calendar: Calendar = .current) -> (value: Double, days: Int)? {
        let window = window(endingAt: end, calendar: calendar)
        let valid = points.filter { window.contains($0.recordedAt) && $0.value.isFinite }
        guard !valid.isEmpty else { return nil }
        let sum = valid.reduce(0.0) { $0 + $1.value }
        return (cumulative ? sum : sum / Double(valid.count), valid.count)
    }
}
