import XCTest
@testable import HealthCore

/// Build 28 P0-1: a day counts as covered only when the user explicitly
/// verified it. A sleep interval, a workout, or a step count never
/// confirms a day on its own: unconfirmed days keep nil sleep and
/// training values, a verified rest day is 0, and a verified training
/// day sums real session RPE. Step counts never reach this layer
/// (RecoveryDataLoader no longer queries them), so the steps-only case
/// is expressed here as records present with neither axis confirmed.
final class RecoveryCoverageTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }

    private let now = Date(timeIntervalSince1970: 86400 * 100)

    private func instant(_ days: Int, _ hours: Int) -> Date {
        now.addingTimeInterval(Double(days * 86400 + hours * 3600))
    }

    private func report(
        sleep: [SleepInterval] = [],
        workouts: [RatedWorkout] = [],
        confirmedSleep: Set<Date> = [],
        confirmedWorkouts: Set<Date> = [],
        target: Double? = 480
    ) -> RecoveryLoadReport {
        RecoveryLoadReport(period: .week, asOf: now, calendar: calendar, targetMinutes: target,
                           sleep: sleep, confirmedSleepDays: confirmedSleep,
                           workouts: workouts, confirmedWorkoutDays: confirmedWorkouts)
    }

    func testUnverifiedDayWithSleepSamplesHasNilSleepMinutes() throws {
        let night = SleepInterval(start: instant(-2, 23), end: instant(-1, 6), stage: .core)
        let result = report(sleep: [night])
        XCTAssertNil(result.days.last?.sleepMinutes)
        XCTAssertNil(result.days.last?.shortfallMinutes)
        XCTAssertEqual(result.sleepCoverageDays, 0)
        XCTAssertNil(result.totalShortfallMinutes)
    }

    func testUnverifiedDayWithRatedWorkoutHasNilTrainingLoad() throws {
        let workout = RatedWorkout(id: UUID(), start: instant(-1, 10), end: instant(-1, 11),
                                   activeMinutes: 50, exertion: 8)
        let result = report(workouts: [workout])
        XCTAssertNil(result.days.last?.trainingLoad)
        XCTAssertEqual(result.loadCoverageDays, 0)
        XCTAssertNil(result.totalTrainingLoad)
    }

    func testVerifiedRestDayHasZeroTrainingLoad() throws {
        let result = report(confirmedWorkouts: [instant(-6, 0)])
        XCTAssertEqual(result.days[1].trainingLoad, 0)
        XCTAssertEqual(result.loadCoverageDays, 1)
        XCTAssertNil(result.days[1].sleepMinutes)
        XCTAssertNil(result.totalTrainingLoad)
    }

    func testVerifiedTrainingDayWithoutExertionHasNilTrainingLoad() throws {
        let workout = RatedWorkout(id: UUID(), start: instant(-1, 10), end: instant(-1, 11),
                                   activeMinutes: 50, exertion: nil)
        let result = report(workouts: [workout], confirmedWorkouts: [instant(-1, 0)])
        XCTAssertNil(result.days.last?.trainingLoad)
        XCTAssertEqual(result.loadCoverageDays, 0)
    }

    func testVerifiedTrainingDayWithExertionSumsSessionLoads() throws {
        let first = RatedWorkout(id: UUID(), start: instant(-1, 10), end: instant(-1, 11),
                                 activeMinutes: 60, exertion: 7)
        let second = RatedWorkout(id: UUID(), start: instant(-1, 18), end: instant(-1, 18) + 1800,
                                  activeMinutes: 30, exertion: 5)
        let result = report(workouts: [first, second], confirmedWorkouts: [instant(-1, 0)])
        XCTAssertEqual(result.days.last?.trainingLoad, 60 * 7 + 30 * 5)
        XCTAssertEqual(result.loadCoverageDays, 1)
    }

    func testOverlappingAndConflictingWorkoutsAreUnresolved() throws {
        let workout = RatedWorkout(id: UUID(), start: instant(-2, 23), end: instant(-1, 1),
                                   activeMinutes: 90, exertion: 4)
        let overlap = RatedWorkout(id: UUID(), start: instant(-2, 22), end: instant(-2, 24) - 60,
                                   activeMinutes: 80, exertion: 5)
        let confirmed: Set<Date> = [instant(-2, 0), instant(-1, 0)]
        XCTAssertNil(report(workouts: [workout, overlap], confirmedWorkouts: confirmed).days.last?.trainingLoad)
        let conflict = RatedWorkout(id: workout.id, start: instant(-2, 23), end: instant(-2, 24) - 60,
                                    activeMinutes: 40, exertion: 4)
        let days = report(workouts: [workout, conflict], confirmedWorkouts: confirmed).days
        XCTAssertNil(days[5].trainingLoad)
        XCTAssertNil(days[6].trainingLoad)
    }

    func testPresenceOfRecordsNeverConfirmsADay() throws {
        let night = SleepInterval(start: instant(-2, 23), end: instant(-1, 6), stage: .core)
        let workout = RatedWorkout(id: UUID(), start: instant(-1, 10), end: instant(-1, 11),
                                   activeMinutes: 50, exertion: 8)
        let result = report(sleep: [night], workouts: [workout])
        XCTAssertNil(result.days.last?.sleepMinutes)
        XCTAssertNil(result.days.last?.trainingLoad)
        XCTAssertEqual(result.sleepCoverageDays, 0)
        XCTAssertEqual(result.loadCoverageDays, 0)
    }

    func testVerifiedSleepDayReturnsMinutesAndShortfall() throws {
        let night = SleepInterval(start: instant(-2, 23), end: instant(-1, 6), stage: .core)
        let result = report(sleep: [night], confirmedSleep: [instant(-1, 0)])
        XCTAssertEqual(result.days.last?.sleepMinutes, 420)
        XCTAssertEqual(result.days.last?.shortfallMinutes, 60)
        XCTAssertEqual(result.sleepCoverageDays, 1)
    }
}
