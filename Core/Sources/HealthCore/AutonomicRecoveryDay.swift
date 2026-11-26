import Foundation

/// Descriptive research inputs: one consistent, source-resolved stream per metric.
/// Supply resting-context HealthKit SDNN (ms), not RMSSD or camera PRV. Daily resting
/// heart rate is context for the day; it is never assigned to an HRV sample's hour.
public struct AutonomicRecoveryDay: Sendable {
    public struct Observation: Sendable {
        public let value: Double
        public let lastSample: Date
        public let sampleCount: Int
        public let referenceDays: Int
        public let baselineMedian: Double?
        public let baselineMiddleHalf: ClosedRange<Double>?

        public var direction: TrendDirection {
            guard let band = baselineMiddleHalf else { return .insufficient }
            if value < band.lowerBound { return .lower }
            if value > band.upperBound { return .higher }
            return .stable
        }
    }

    public struct Hour: Sendable {
        public let start: Date
        public let restingSDNN: Observation?
    }

    public enum Pattern: String, Sendable {
        case insufficient = "个人基线或当日采样不足"
        case higherStrain = "HRV 偏低且静息心率偏高"
        case lowerStrain = "HRV 偏高且静息心率偏低"
        case noConcordantShift = "两项指标未见同向负荷变化"
    }

    public let asOf: Date
    public let hours: [Hour]
    public let dailySDNN: Observation?
    public let dailyRestingBPM: Observation?
    public var observedHours: Int { hours.filter { $0.restingSDNN != nil }.count }
    public var comparableHours: Int { hours.filter { $0.restingSDNN?.baselineMedian != nil }.count }
    /// Denominator is the elapsed local hour buckets up to and including asOf's hour.
    public var observedHourFraction: Double { hours.isEmpty ? 0 : Double(observedHours) / Double(hours.count) }

    /// Concordance is context for a recovery journal, not a validated stress or fatigue scale.
    public var pattern: Pattern {
        guard let hrv = dailySDNN?.direction, let pulse = dailyRestingBPM?.direction,
              hrv != .insufficient, pulse != .insufficient else { return .insufficient }
        if hrv == .lower && pulse == .higher { return .higherStrain }
        if hrv == .higher && pulse == .lower { return .lowerStrain }
        return .noConcordantShift
    }

    public init(restingSDNN: [TrendPoint], restingBPM: [TrendPoint], asOf: Date, calendar: Calendar = .current) {
        self.asOf = asOf
        let start = calendar.startOfDay(for: asOf)
        let oldest = calendar.date(byAdding: .day, value: -30, to: start)!
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: start)!

        // Identical timestamps can be re-imports. Conflicting duplicates have no unambiguous value.
        func clean(_ input: [TrendPoint]) -> [TrendPoint] {
            let eligible = input.filter { $0.recordedAt >= oldest && $0.recordedAt <= asOf && $0.value.isFinite && $0.value > 0 }
            return Dictionary(grouping: eligible, by: \.recordedAt).compactMap { _, repeats in
                let first = repeats[0]
                return repeats.allSatisfy { $0.value == first.value } ? first : nil
            }.sorted { $0.recordedAt < $1.recordedAt }
        }

        func median(_ points: [TrendPoint]) -> Double {
            let sorted = points.map(\.value).sorted(), mid = sorted.count / 2
            return sorted.count.isMultiple(of: 2) ? sorted[mid - 1] / 2 + sorted[mid] / 2 : sorted[mid]
        }

        func summarize(_ current: [TrendPoint], history: [TrendPoint]) -> Observation? {
            guard let last = current.last else { return nil }
            let daily = Dictionary(grouping: history, by: { calendar.startOfDay(for: $0.recordedAt) })
                .map { TrendPoint(recordedAt: $0.key, value: median($0.value)) }
            // Reuse the trend card's 7/30 distinct-day policy and interpolated middle half.
            let reference = DailyTrendProfile(points: daily, end: tomorrow, calendar: calendar).baseline
            return Observation(value: median(current), lastSample: last.recordedAt, sampleCount: current.count,
                               referenceDays: reference.count, baselineMedian: reference.median,
                               baselineMiddleHalf: reference.middleHalf)
        }
        let sdnn = clean(restingSDNN), pulse = clean(restingBPM)
        let today = sdnn.filter { $0.recordedAt >= start }
        let history = sdnn.filter { $0.recordedAt < start }
        // For a partial day, compare with the same local wall-clock cutoff on prior days.
        func clock(_ instant: Date) -> Int {
            let time = calendar.dateComponents([.hour, .minute, .second], from: instant)
            return time.hour! * 3600 + time.minute! * 60 + time.second!
        }
        let cutoff = clock(asOf)
        dailySDNN = summarize(today, history: history.filter { clock($0.recordedAt) <= cutoff })
        dailyRestingBPM = summarize(pulse.filter { $0.recordedAt >= start },
                                    history: pulse.filter { $0.recordedAt < start && clock($0.recordedAt) <= cutoff })
        let byHour = Dictionary(grouping: today) { calendar.dateInterval(of: .hour, for: $0.recordedAt)!.start }
        let pastByClockHour = Dictionary(grouping: history) { calendar.component(.hour, from: $0.recordedAt) }
        var bins: [Hour] = []
        var cursor = start
        while cursor <= asOf, let hour = calendar.dateInterval(of: .hour, for: cursor), hour.end > cursor {
            let historical = pastByClockHour[calendar.component(.hour, from: cursor)] ?? []
            let comparable = hour.end <= asOf ? historical : historical.filter { clock($0.recordedAt) <= cutoff }
            bins.append(Hour(start: cursor, restingSDNN: summarize(byHour[cursor] ?? [], history: comparable)))
            cursor = hour.end
        }
        hours = bins
    }
}
