import XCTest
@testable import HealthCore

final class RecoveryJournalTests: XCTestCase {
    var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = .gmt
        return cal
    }
    func instant(_ day: Int, hour: Int = 0) -> Date { Date(timeIntervalSince1970: Double(day * 86400 + hour * 3600)) }
    func makeJournal(hours: [Int], energies: [TrendPoint], snapshots: [AutonomicRecoveryDay] = []) -> RecoveryJournal {
        let sleep = hours.enumerated().map { i, amount in
            SleepInterval(start: instant(i + 1), end: instant(i + 1, hour: amount), stage: .core)
        }
        let known = Set((1...7).map { instant($0) })
        let report = RecoveryLoadReport(period: .week, asOf: instant(8), calendar: calendar, targetMinutes: 480,
                                       sleep: sleep, confirmedSleepDays: known, workouts: [], confirmedWorkoutDays: known)
        return RecoveryJournal(report: report, autonomic: snapshots, energy: energies, fatigue: [])
    }
    func testTiedRanksAndConstantSeries() throws {
        let sleep = [5, 5, 6, 7, 7, 8, 8]
        let values = sleep.enumerated().map { TrendPoint(recordedAt: instant($0.offset + 1, hour: 18), value: 10 - Double($0.element)) }
        let journal = makeJournal(hours: sleep, energies: values)
        XCTAssertEqual(journal.sleepAndLaterEnergy.pairedDays, 7)
        XCTAssertEqual(try XCTUnwrap(journal.sleepAndLaterEnergy.rho), -1, accuracy: 1e-10)
        XCTAssertNil(makeJournal(hours: Array(repeating: 8, count: 7), energies: values).sleepAndLaterEnergy.rho)
        XCTAssertEqual(journal.days.last?.energyChange, 0)
        XCTAssertNil(journal.days.last?.fatigue)
    }

    func testOnlyActualComparableObservationsContribute() {
        let points = [TrendPoint(recordedAt: instant(1, hour: 18), value: 5),
                      TrendPoint(recordedAt: instant(2, hour: 7), value: 6),
                      TrendPoint(recordedAt: instant(3, hour: 20), value: 2),
                      TrendPoint(recordedAt: instant(3, hour: 20), value: 9),
                      TrendPoint(recordedAt: instant(4, hour: 16), value: 0),
                      TrendPoint(recordedAt: instant(5, hour: 16), value: 11)]
        let source = (-9...4).map { TrendPoint(recordedAt: instant($0, hour: 9), value: 44) }
        let snapshots = (1...4).map { AutonomicRecoveryDay(restingSDNN: source, restingBPM: [], asOf: instant($0, hour: 23), calendar: calendar) }
        let journal = makeJournal(hours: Array(repeating: 7, count: 7), energies: points, snapshots: snapshots)
        XCTAssertEqual(journal.sleepAndLaterEnergy.pairedDays, 2)
        XCTAssertNil(journal.days[2].energy)
        XCTAssertNil(journal.days[3].energyChange)
        XCTAssertEqual(journal.days[3].energy?.value, 0)
        XCTAssertNil(journal.days[4].energy)
        XCTAssertEqual(journal.previousLoadAndSDNN.pairedDays, 3)
        XCTAssertEqual(journal.sleepAndLaterSDNN.pairedDays, 0)
        XCTAssertNil(journal.previousLoadAndSDNN.rho)
    }
}
