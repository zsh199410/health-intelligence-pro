import Foundation

public enum SleepCalculator {
    /// Deduplicate same-stage and conflicting-stage intervals with a deterministic sweep.
    /// With no source identifier in the input, a stage precedence is used when sources conflict:
    /// awake > deep > REM > core > unspecified. This is NOT a clinical stage arbitration.
    public static func summarize(_ intervals: [SleepInterval]) -> SleepSummary {
        var secondsByStage: [SleepStage: TimeInterval] = [:]
        for segment in segments(intervals) {
            secondsByStage[segment.stage, default: 0] += segment.end.timeIntervalSince(segment.start)
        }
        var minutes: [SleepStage: Int] = [:]
        for stage in SleepStage.allCases { minutes[stage] = Int(((secondsByStage[stage] ?? 0) / 60).rounded()) }
        let asleep = [SleepStage.deep, .rem, .core, .unspecified].reduce(0) { $0 + (minutes[$1] ?? 0) }
        return SleepSummary(minutesByStage: minutes, totalAsleepMinutes: asleep,
                            minutesAwake: minutes[.awake] ?? 0)
    }

    /// Deduplicated time-ordered segments for the sleep stage timeline.
    /// Same sweep as `summarize` (same stage precedence for conflicting
    /// sources), but keeps the (start, end, stage) pieces instead of
    /// collapsing them to minutes. Adjacent pieces with the same stage
    /// are merged. Returns [] when there is no usable interval.
    public static func segments(_ intervals: [SleepInterval]) -> [SleepInterval] {
        // Track the count for each stage, since duplicate sources can overlap.
        // Applying all deltas at a timestamp preserves half-open interval semantics.
        var changes: [Date: [SleepStage: Int]] = [:]
        for interval in intervals where interval.end > interval.start {
            changes[interval.start, default: [:]][interval.stage, default: 0] += 1
            changes[interval.end, default: [:]][interval.stage, default: 0] -= 1
        }
        let boundaries = changes.keys.sorted()
        let precedence: [SleepStage] = [.awake, .deep, .rem, .core, .unspecified]
        var active: [SleepStage: Int] = [:]
        var pieces: [SleepInterval] = []
        for (start, end) in zip(boundaries, boundaries.dropFirst()) {
            for (stage, delta) in changes[start, default: [:]] {
                active[stage, default: 0] += delta
            }
            guard let winningStage = precedence.first(where: { active[$0, default: 0] > 0 }) else { continue }
            if let last = pieces.last, last.stage == winningStage, last.end == start {
                pieces[pieces.count - 1] = SleepInterval(start: last.start, end: end, stage: winningStage)
            } else {
                pieces.append(SleepInterval(start: start, end: end, stage: winningStage))
            }
        }
        return pieces
    }
}
