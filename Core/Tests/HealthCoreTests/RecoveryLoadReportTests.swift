import XCTest
@testable import HealthCore

final class RecoveryLoadReportTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = .gmt
        return value
    }
    private let now = Date(timeIntervalSince1970: 86400 * 100)
    private func instant(_ days: Int, _ hours: Int) -> Date {
        now.addingTimeInterval(Double(days * 86400 + hours * 3600))
    }
    private func report(_ sleep: [SleepInterval] = [], _ workouts: [RatedWorkout] = [],
                        missing: Set<Date> = [], target: Double? = 480) -> RecoveryLoadReport {
        let confirmed = Set((-7 ... -1).map { instant($0, 0) }).subtracting(missing)
        return RecoveryLoadReport(period: .week, asOf: now, calendar: calendar, targetMinutes: target,
                                  sleep: sleep, confirmedSleepDays: confirmed, workouts: workouts,
                                  confirmedWorkoutDays: confirmed)
    }

    func testSleepDebtDeduplicatesCrossMidnightAndSplitsNapsAtNoon() throws {
        let night = SleepInterval(start: instant(-2, 23), end: instant(-1, 6), stage: .core)
        let awake = SleepInterval(start: instant(-1, 1), end: instant(-1, 2), stage: .awake)
        let nap = SleepInterval(start: instant(-1, 11), end: instant(-1, 13), stage: .unspecified)
        let result = report([night, night, awake, nap])
        XCTAssertEqual(result.days.last?.sleepMinutes, 420)
        XCTAssertEqual(result.days.last?.shortfallMinutes, 60)
        XCTAssertEqual(result.days.last?.latestSleepSampleEnd, nap.end)
        XCTAssertEqual(result.totalShortfallMinutes, 6 * 480 + 60)
        XCTAssertNil(report(target: .infinity).totalShortfallMinutes)
    }

    func testMissingDayOrUnratedSessionDoesNotBecomeZero() throws {
        let missing = instant(-7, 0)
        let session = RatedWorkout(id: UUID(), start: instant(-1, 10), end: instant(-1, 11), activeMinutes: 50, exertion: nil)
        let result = report([], [session], missing: [missing])
        XCTAssertEqual(result.sleepCoverageDays, 6)
        XCTAssertEqual(result.loadCoverageDays, 5)
        XCTAssertNil(result.days.first?.sleepMinutes)
        XCTAssertNil(result.totalTrainingLoad)
        XCTAssertNil(result.totalShortfallMinutes)
        XCTAssertEqual(result.days[1].trainingLoad, 0)
        XCTAssertNil(result.days.last?.trainingLoad)
    }

    func testWorkoutUsesRealExertionActiveMinutesAndCompletionDay() throws {
        let workout = RatedWorkout(id: UUID(), start: instant(-2, 23), end: instant(-1, 1), activeMinutes: 90, exertion: 4)
        let rated = report([], [workout, workout])
        XCTAssertEqual(rated.totalTrainingLoad, 360)
        XCTAssertEqual(rated.days.last?.trainingLoad, 360)
        XCTAssertEqual(rated.days.last?.latestWorkoutEnd, workout.end)
        let overlap = RatedWorkout(id: UUID(), start: instant(-2, 22), end: instant(-2, 24) - 60, activeMinutes: 80, exertion: 5)
        XCTAssertNil(report([], [workout, overlap]).days.last?.trainingLoad)
        let conflict = RatedWorkout(id: workout.id, start: instant(-2, 23), end: instant(-2, 24) - 60, activeMinutes: 40, exertion: 4)
        let days = report([], [workout, conflict]).days
        XCTAssertNil(days[5].trainingLoad)
        XCTAssertNil(days[6].trainingLoad)
    }
}
