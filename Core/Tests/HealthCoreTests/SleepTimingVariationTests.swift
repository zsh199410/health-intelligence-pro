import XCTest
@testable import HealthCore

final class SleepTimingVariationTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2024, month: 3, day: day, hour: hour, minute: minute))!
    }
    private func sleep(_ start: Date, _ end: Date, _ stage: SleepStage = .core) -> SleepInterval {
        SleepInterval(start: start, end: end, stage: stage)
    }

    func testPicksLongestObservedSleepAndWrapsOnsetsAtMidnight() {
        let first = sleep(date(6, 23, 55), date(7, 7))
        let second = sleep(date(8, 0, 5), date(8, 7, 20))
        let nap = sleep(date(7, 15), date(7, 16))
        let result = SleepTimingVariation.evaluate([nap, second, first, first], endingAt: date(9, 14), calendar: calendar)
        XCTAssertEqual(result.observedDays, 2)
        XCTAssertEqual(result.adjacentPairs, 1)
        XCTAssertEqual(result.medianOnsetChange, 10)
        XCTAssertEqual(result.medianWakeChange, 20)
    }

    func testClockTimesRemainComparableAcrossSpringDST() {
        let result = SleepTimingVariation.evaluate([
            sleep(date(8, 23), date(9, 7)), sleep(date(9, 23), date(10, 7))
        ], endingAt: date(11, 12), calendar: calendar)
        XCTAssertEqual(result.medianOnsetChange, 0)
        XCTAssertEqual(result.medianWakeChange, 0)
    }

    func testOnlyCompleteWakeDatesAndAdjacentDaysCount() {
        let result = SleepTimingVariation.evaluate([
            sleep(date(1, 22), date(2, 6)), sleep(date(3, 22), date(4, 6)),
            sleep(date(4, 22), date(5, 6), .awake),
            sleep(date(5, 22), date(6, 6)), sleep(date(9, 22), date(10, 6))
        ], endingAt: date(10, 12), calendar: calendar)
        XCTAssertEqual(result.observedDays, 2)
        XCTAssertEqual(result.adjacentPairs, 0)
        XCTAssertNil(result.medianOnsetChange)
        XCTAssertNil(result.medianWakeChange)
    }
}
