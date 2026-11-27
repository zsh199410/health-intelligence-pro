import Foundation

/// Time-stamped personal energy and fatigue ratings (0–10, reported independently).
/// Higher ratings mean more of that specific sensation. Do not impute either from HRV.
public struct RecoveryJournal: Sendable {
    public struct Day: Sendable {
        public let load: RecoveryLoadReport.Day
        public let autonomic: AutonomicRecoveryDay?
        public let energy: TrendPoint?
        public let fatigue: TrendPoint?
        /// Change from the immediately preceding calendar day's reported energy, when present.
        public let energyChange: Double?
        public let fatigueChange: Double?
    }
    public struct Association: Sendable {
        public let pairedDays: Int
        /// Descriptive Spearman rank correlation (midranks for ties). A minimum of
        /// seven pairs is a display policy, not a significance or causality test.
        public let rho: Double?

        fileprivate init(_ pairs: [(Double, Double)]) {
            pairedDays = pairs.count
            guard pairs.count >= 7 else { rho = nil; return }
            func ranks(_ values: [Double]) -> [Double] {
                let order = values.indices.sorted { values[$0] < values[$1] }
                var output = Array(repeating: 0.0, count: values.count)
                var start = 0
                while start < order.count {
                    var end = start + 1
                    while end < order.count && values[order[end]] == values[order[start]] { end += 1 }
                    let rank = Double(start + end - 1) / 2
                    for index in order[start..<end] { output[index] = rank }
                    start = end
                }
                return output
            }
            let center = Double(pairs.count - 1) / 2
            let x = ranks(pairs.map { $0.0 }).map { $0 - center }
            let y = ranks(pairs.map { $0.1 }).map { $0 - center }
            let norm = sqrt(x.reduce(0) { $0 + $1 * $1 } * y.reduce(0) { $0 + $1 * $1 })
            rho = norm > 0 ? max(-1, min(1, zip(x, y).reduce(0) { $0 + $1.0 * $1.1 } / norm)) : nil
        }
    }
    public let days: [Day]
    public let sleepAndLaterEnergy: Association
    /// Previous day's training load and next day's SDNN change relative to that day's baseline.
    public let previousLoadAndSDNN: Association
    public let sleepAndLaterSDNN: Association

    public init(report: RecoveryLoadReport, autonomic: [AutonomicRecoveryDay],
                energy: [TrendPoint], fatigue: [TrendPoint]) {
        let calendar = report.calendar
        // Use report day boundaries for every input; a different travel time zone must
        // be handled by rebuilding the source report and autonomic snapshots together.
        func lastRatings(_ points: [TrendPoint]) -> [Date: TrendPoint] {
            let valid = points.filter { (0...10).contains($0.value) && $0.recordedAt <= report.asOf }
            return Dictionary(grouping: valid, by: { calendar.startOfDay(for: $0.recordedAt) }).compactMapValues { samples in
                guard let last = samples.max(by: { $0.recordedAt < $1.recordedAt }),
                      samples.allSatisfy({ $0.recordedAt != last.recordedAt || $0.value == last.value }) else { return nil }
                return last
            }
        }
        let energies = lastRatings(energy), fatigues = lastRatings(fatigue)
        let snapshots = Dictionary(grouping: autonomic.filter { $0.asOf <= report.asOf },
                                   by: { calendar.startOfDay(for: $0.asOf) })
        var result: [Day] = []
        var sleepEnergy: [(Double, Double)] = [], loadSDNN: [(Double, Double)] = [], sleepSDNN: [(Double, Double)] = []
        for load in report.days {
            let energy = energies[load.date], fatigue = fatigues[load.date]
            let previous = result.last
            let snapshotsForDay = snapshots[load.date] ?? []
            let latest = snapshotsForDay.map(\.asOf).max()
            let candidates = snapshotsForDay.filter { $0.asOf == latest && $0.hours.first?.start == load.date }
            let snapshot = candidates.count == 1 ? candidates[0] : nil
            if let sleep = load.sleepMinutes, let energy, energy.recordedAt >= load.sleepWindow.end {
                sleepEnergy.append((sleep, energy.value))
            }
            // Use one actually sampled resting HRV hour per day (most recent comparable hour).
            // Do not move a morning sample to the report's later creation timestamp.
            if let hourly = snapshot?.hours.compactMap(\.restingSDNN).last(where: { $0.baselineMedian != nil }),
               let baseline = hourly.baselineMedian, baseline > 0 {
                let change = (hourly.value - baseline) / baseline
                if let priorLoad = previous?.load.trainingLoad { loadSDNN.append((priorLoad, change)) }
                if let sleep = load.sleepMinutes, hourly.lastSample >= load.sleepWindow.end {
                    sleepSDNN.append((sleep, change))
                }
            }
            func change(_ value: TrendPoint?, _ prior: TrendPoint?) -> Double? {
                guard let value, let prior else { return nil }
                return value.value - prior.value
            }
            result.append(Day(load: load, autonomic: snapshot, energy: energy, fatigue: fatigue,
                              energyChange: change(energy, previous?.energy),
                              fatigueChange: change(fatigue, previous?.fatigue)))
        }
        days = result
        sleepAndLaterEnergy = Association(sleepEnergy)
        previousLoadAndSDNN = Association(loadSDNN)
        sleepAndLaterSDNN = Association(sleepSDNN)
    }
}
