import XCTest
@testable import HealthCore

final class SleepHistoryTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    private func interval(_ start: Date, _ end: Date, _ stage: SleepStage = .core) -> SleepInterval {
        SleepInterval(start: start, end: end, stage: stage)
    }

    /// 2026-11-20 12:00 UTC, so the 7-day window is 2026-11-14 .. 2026-11-20.
    private var now: Date { date(2026, 11, 20, 12) }

    func testEmptyIntervalsYieldSevenRecordlessDays() {
        let days = SleepHistory.days(from: [], days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertTrue(days.allSatisfy { !$0.hasRecord && $0.asleepMinutes == 0 })
        XCTAssertEqual(days.first?.date, date(2026, 11, 14, 0))
        XCTAssertEqual(days.last?.date, date(2026, 11, 20, 0))
    }

    func testSingleNightAttributedToWakeDate() {
        let night = interval(date(2026, 11, 19, 23), date(2026, 11, 20, 7))
        let days = SleepHistory.days(from: [night], days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 20, 0) })?.asleepMinutes, 480)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 19, 0) })?.asleepMinutes, 0)
    }

    func testAwakeMinutesDoNotCountAsSleep() {
        let intervals = [
            interval(date(2026, 11, 19, 23), date(2026, 11, 20, 6)),
            interval(date(2026, 11, 20, 6), date(2026, 11, 20, 7), .awake)
        ]
        let days = SleepHistory.days(from: intervals, days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 20, 0) })?.asleepMinutes, 420)
    }

    func testDuplicateSourcesCountedOnce() {
        let night = interval(date(2026, 11, 19, 23), date(2026, 11, 20, 7))
        let days = SleepHistory.days(from: [night, night], days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 20, 0) })?.asleepMinutes, 480)
    }

    func testFutureSamplesExcluded() {
        let future = interval(date(2026, 11, 20, 13), date(2026, 11, 20, 21))
        let days = SleepHistory.days(from: [future], days: 7, endingAt: now, calendar: calendar)
        XCTAssertTrue(days.allSatisfy { !$0.hasRecord })
    }

    func testWindowClippingCountsOnlyInWindowMinutes() {
        // 2026-11-12 22:00 -> 2026-11-14 06:00; only 00:00-06:00 on 11-14 is in window.
        let long = interval(date(2026, 11, 12, 22), date(2026, 11, 14, 6))
        let days = SleepHistory.days(from: [long], days: 7, endingAt: now, calendar: calendar)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 14, 0) })?.asleepMinutes, 360)
        XCTAssertEqual(days.first(where: { $0.date == date(2026, 11, 13, 0) })?.asleepMinutes, 0)
    }

    func testZeroDaysReturnsEmpty() {
        XCTAssertTrue(SleepHistory.days(from: [], days: 0, endingAt: now, calendar: calendar).isEmpty)
    }
}
