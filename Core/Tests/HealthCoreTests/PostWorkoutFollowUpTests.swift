import XCTest
@testable import HealthCore

final class PostWorkoutFollowUpTests: XCTestCase {
    private var utc: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal
    }
    private func time(_ day: Int, _ hour: Double) -> Date {
        Date(timeIntervalSince1970: Double(day) * 86400 + hour * 3600)
    }
    private func session(_ start: Date, _ end: Date) -> RatedWorkout {
        RatedWorkout(id: UUID(), start: start, end: end, activeMinutes: end.timeIntervalSince(start) / 60, exertion: nil)
    }
    func testOnlyAfterExerciseBeforeNextWorkoutAndNoStraddlingHRVMedian() throws {
        let workout = session(time(10, 7), time(10, 8.5))
        let next = session(time(11, 9), time(11, 10))
        var source = (-5...10).flatMap { day in
            [8.0, 9.0].map { TrendPoint(recordedAt: time(day, $0), value: 50) }
        }
        source.append(TrendPoint(recordedAt: time(10, 8.75), value: 20))
        let day = AutonomicRecoveryDay(restingSDNN: source, restingBPM: [], asOf: time(10, 23), calendar: utc)
        let load = RecoveryLoadReport(period: .week, asOf: time(13, 12), calendar: utc, targetMinutes: nil,
                                      sleep: [], confirmedSleepDays: [], workouts: [workout, next], confirmedWorkoutDays: [])
        let journal = RecoveryJournal(report: load, autonomic: [day], energy: [
            TrendPoint(recordedAt: time(10, 20), value: 5), TrendPoint(recordedAt: next.start, value: 8)
        ], fatigue: [])
        let result = try XCTUnwrap(PostWorkoutFollowUp(workout: workout, otherWorkouts: [workout, next], journal: journal, asOf: load.asOf))
        XCTAssertEqual(result.windowEnd, next.start)
        XCTAssertEqual(result.restingSDNNHours.map(\.lastSample), [time(10, 9)])
        XCTAssertEqual(result.energyRatings.map(\.value), [5])
        XCTAssertTrue(result.fatigueRatings.isEmpty)
        let earlier = try XCTUnwrap(PostWorkoutFollowUp(workout: workout, otherWorkouts: [next], journal: journal, asOf: time(10, 9.5)))
        XCTAssertTrue(earlier.energyRatings.isEmpty)
        XCTAssertEqual(earlier.windowEnd, time(10, 9.5))
        XCTAssertNil(PostWorkoutFollowUp(workout: workout, otherWorkouts: [session(time(10, 8), time(10, 9))],
                                         journal: journal, asOf: load.asOf))
    }
}
