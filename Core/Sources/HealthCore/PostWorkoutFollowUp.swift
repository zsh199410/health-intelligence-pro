import Foundation

/// Retrospective recovery diary for one workout. Collects observed changes for
/// at most 48 elapsed hours, stopping at the start of the next known workout.
/// It does not infer fitness to train or assign a recovery countdown.
public struct PostWorkoutFollowUp: Sendable {
    public let workoutID: UUID
    public let workoutEndedAt: Date
    public let windowEnd: Date
    public let restingSDNNHours: [AutonomicRecoveryDay.Observation]
    public let energyRatings: [TrendPoint]
    public let fatigueRatings: [TrendPoint]

    public init?(workout: RatedWorkout, otherWorkouts: [RatedWorkout], journal: RecoveryJournal, asOf: Date) {
        guard workout.start < workout.end, workout.end <= asOf else { return nil }
        let others = otherWorkouts.filter { $0.start <= asOf && $0.end > $0.start }
        // Ambiguous workout revisions or overlapping sessions prevent attribution.
        guard others.allSatisfy({ other in
            if other.id == workout.id { return other.start == workout.start && other.end == workout.end }
            return other.start >= workout.end || other.end <= workout.start
        }) else { return nil }
        workoutID = workout.id
        workoutEndedAt = workout.end
        let limit = workout.end.addingTimeInterval(48 * 3600)
        let next = others.filter { $0.id != workout.id && $0.start >= workout.end }.map(\.start).min()
        let through = min(asOf, min(next ?? limit, limit))
        windowEnd = through
        func inWindow(_ date: Date) -> Bool {
            date > workout.end && date <= through && date != next
        }
        energyRatings = journal.days.compactMap(\.energy).filter { inWindow($0.recordedAt) }
        fatigueRatings = journal.days.compactMap(\.fatigue).filter { inWindow($0.recordedAt) }
        restingSDNNHours = journal.days.compactMap(\.autonomic).flatMap(\.hours).compactMap { hour in
            // A median can include earlier samples than its last timestamp.
            // Discard the straddling hour so pre-exercise samples cannot leak into recovery.
            guard hour.start >= workout.end, let observation = hour.restingSDNN,
                  observation.baselineMedian != nil, inWindow(observation.lastSample) else { return nil }
            return observation
        }
    }
}
