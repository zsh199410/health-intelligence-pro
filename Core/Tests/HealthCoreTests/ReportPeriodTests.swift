import XCTest
@testable import HealthCore

final class ReportPeriodTests: XCTestCase {
    func testWeekUsesLocalMidnightAcrossSpringClockChange() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/Los_Angeles"))
        let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12)))
        let start = try XCTUnwrap(calendar.date(from: DateComponents(year: 2025, month: 3, day: 4)))
        XCTAssertEqual(ReportPeriod.week.window(endingAt: end, calendar: calendar), start...end)
    }

    func testMissingDaysAreExcludedAndZeroIsARealRecord() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let end = Date(timeIntervalSince1970: 1_728_000_000)
        let start = ReportPeriod.week.window(endingAt: end, calendar: calendar).lowerBound
        let points = [
            TrendPoint(recordedAt: start.addingTimeInterval(-1), value: 200),
            TrendPoint(recordedAt: start, value: 0),
            TrendPoint(recordedAt: end.addingTimeInterval(-86_400), value: .nan),
            TrendPoint(recordedAt: end, value: 20),
            TrendPoint(recordedAt: end.addingTimeInterval(1), value: 200)
        ]
        let mean = try XCTUnwrap(ReportPeriod.week.summarize(points, endingAt: end, cumulative: false, calendar: calendar))
        XCTAssertEqual(mean.days, 2)
        XCTAssertEqual(mean.value, 10)
        XCTAssertEqual(ReportPeriod.week.summarize(points, endingAt: end, cumulative: true, calendar: calendar)?.value, 20)
        XCTAssertNil(ReportPeriod.day.summarize([], endingAt: end, cumulative: true, calendar: calendar))
    }
}
