import Foundation

/// Source-resolved workouts. The supplied active duration excludes pauses;
/// session RPE is a real user rating on the 0–10 scale (Foster et al., 2001).
public struct RatedWorkout: Equatable, Sendable {
    public let id: UUID
    public let start: Date
    public let end: Date
    public let activeMinutes: Double
    public let exertion: Double?

    public init(id: UUID, start: Date, end: Date, activeMinutes: Double, exertion: Double?) {
        self.id = id
        self.start = start
        self.end = end
        self.activeMinutes = activeMinutes
        self.exertion = exertion
    }

    fileprivate var load: Double? {
        guard end > start, activeMinutes.isFinite, activeMinutes > 0,
              activeMinutes <= end.timeIntervalSince(start) / 60,
              let exertion, (0...10).contains(exertion) else { return nil }
        return activeMinutes * exertion
    }
}

/// Daily observations for a completed-day report. Coverage confirmations must
/// come from the caller's independently established coverage; the presence of a
/// HealthKit sample or a successful empty query does not establish completeness.
public struct RecoveryLoadReport: Sendable {
    public enum Period: Int, Sendable { case week = 7, month = 30, quarter = 90 }

    public struct Day: Sendable {
        public let date: Date
        /// Sleep attributed to the local noon ending on date, including naps before that noon.
        public let sleepWindow: DateInterval
        public let sleepMinutes: Double?
        public let latestSleepSampleEnd: Date?
        public let latestWorkoutEnd: Date?
        public let shortfallMinutes: Double?
        /// Arbitrary session-RPE units, assigned to the workout completion day.
        public let trainingLoad: Double?
    }

    public let asOf: Date
    public let days: [Day]
    public let sleepTargetMinutes: Double?
    public var sleepCoverageDays: Int { days.compactMap(\.sleepMinutes).count }
    public var loadCoverageDays: Int { days.compactMap(\.trainingLoad).count }

    /// Accumulated shortfall against the explicit personal target. A longer night
    /// adds zero; this describes missed target minutes, not physiological debt repayment.
    public var totalShortfallMinutes: Double? { completeTotal(days.map(\.shortfallMinutes)) }
    public var totalTrainingLoad: Double? { completeTotal(days.map(\.trainingLoad)) }

    private func completeTotal(_ values: [Double?]) -> Double? {
        guard values.allSatisfy({ $0 != nil }) else { return nil }
        return values.compactMap { $0 }.reduce(0, +)
    }

    public init(period: Period, asOf: Date, calendar: Calendar = .current, targetMinutes: Double?,
                sleep: [SleepInterval], confirmedSleepDays: Set<Date>,
                workouts: [RatedWorkout], confirmedWorkoutDays: Set<Date>) {
        self.asOf = asOf
        let target = targetMinutes.flatMap { $0.isFinite && $0 > 0 && $0 <= 1440 ? $0 : nil }
        sleepTargetMinutes = target
        let today = calendar.startOfDay(for: asOf)
        let firstDay = calendar.date(byAdding: .day, value: -period.rawValue, to: today)!
        let firstNoon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: firstDay)!
        let begin = calendar.date(byAdding: .day, value: -1, to: firstNoon)!
        let completeSleep = Set(confirmedSleepDays.map { calendar.startOfDay(for: $0) })
        let completeActivity = Set(confirmedWorkoutDays.map { calendar.startOfDay(for: $0) })
        let pieces = SleepCalculator.segments(sleep.filter { $0.end > begin && $0.start < today && $0.end <= asOf })
            .filter { $0.stage != .awake }

        // Exact re-imports collapse. Mark every implicated day incomplete if
        // conflicting versions share an ID or overlapping recordings describe the same effort.
        let usable = workouts.filter { $0.end <= asOf }
        var unresolved = Set<Date>()
        var unique: [RatedWorkout] = []
        for group in Dictionary(grouping: usable, by: \.id).values {
            let first = group[0]
            if group.allSatisfy({ $0 == first }) {
                unique.append(first)
            } else {
                unresolved.formUnion(group.map { calendar.startOfDay(for: $0.end) })
            }
        }
        var latestEnd: Date?
        for workout in unique.sorted(by: { $0.start < $1.start }) {
            if let end = latestEnd, workout.start < end {
                unresolved.insert(calendar.startOfDay(for: end))
                unresolved.insert(calendar.startOfDay(for: workout.end))
            }
            latestEnd = max(latestEnd ?? workout.end, workout.end)
        }
        let byDay = Dictionary(grouping: unique, by: { calendar.startOfDay(for: $0.end) })
        days = (0..<period.rawValue).map { offset in
            let date = calendar.date(byAdding: .day, value: offset, to: firstDay)!
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
            let window = DateInterval(start: calendar.date(byAdding: .day, value: -1, to: noon)!, end: noon)
            let inWindow = pieces.filter { $0.start < window.end && $0.end > window.start }
            let asleep: Double? = completeSleep.contains(date) ? inWindow.reduce(0.0) { result, piece in
                result + max(0, min(piece.end, window.end).timeIntervalSince(max(piece.start, window.start))) / 60
            } : nil
            let sessions = byDay[date] ?? [], loads = sessions.compactMap(\.load)
            let known = completeActivity.contains(date) && !unresolved.contains(date) && loads.count == sessions.count
            return Day(date: date, sleepWindow: window, sleepMinutes: asleep,
                       latestSleepSampleEnd: sleep.filter { $0.end <= asOf && $0.end > $0.start && $0.start < window.end && $0.end > window.start }.map(\.end).max(),
                       latestWorkoutEnd: sessions.map(\.end).max(),
                       shortfallMinutes: target.flatMap { goal in asleep.map { max(0, goal - $0) } },
                       trainingLoad: known ? loads.reduce(0, +) : nil)
        }
    }
}
