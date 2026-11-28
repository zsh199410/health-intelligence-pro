import XCTest
@testable import HealthCore

final class DailyTrendProfileTests: XCTestCase {
    let utc: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }()

    func testBaselineUsesSevenPriorDistinctDaysAndResistsOutlier() {
        let end = Date(timeIntervalSince1970: 100 * 86_400 + 3600)
        func point(_ day: Int, _ value: Double) -> TrendPoint {
            TrendPoint(recordedAt: utc.date(byAdding: .day, value: day, to: utc.startOfDay(for: end))!, value: value)
        }
        let input = [point(-9, 0), point(-9, 2), point(-8, 1), point(-7, 2), point(-6, 2),
                     point(-5, 2), point(-4, 3), point(-3, 999), point(-1, 0), point(0, 44), point(1, 55)]
        let profile = DailyTrendProfile(points: input, end: end, calendar: utc)
        XCTAssertEqual(profile.baseline.count, 7)
        XCTAssertEqual(profile.baseline.median, 2)
        XCTAssertEqual(profile.baseline.yesterday, 0)
        XCTAssertEqual(profile.runs(days: 7).map(\.count), [4, 2])
        XCTAssertNil(DailyTrendProfile(points: Array(input.dropFirst(2)), end: end, calendar: utc).baseline.median)
        XCTAssertTrue(DailyTrendProfile(points: [], end: end, calendar: utc).runs(days: 90).isEmpty)
    }

    func testTodayDoesNotUseYesterdaysBucketWhenMissing() {
        let end = Date(timeIntervalSince1970: 100 * 86_400 + 3600)
        let yesterday = TrendPoint(recordedAt: end.addingTimeInterval(-86_400), value: 12)
        XCTAssertNil(DailyTrendProfile(points: [yesterday], end: end, calendar: utc).todayValue)
        let today = TrendPoint(recordedAt: utc.startOfDay(for: end), value: 0)
        XCTAssertEqual(DailyTrendProfile(points: [today, yesterday], end: end, calendar: utc).todayValue, 0)
    }

    func testYesterdayMatchesDurationAcrossDSTOrRejectsImpossibleWindow() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        let expected = c.date(from: DateComponents(year: 2023, month: 3, day: 11, hour: 12))!
        XCTAssertEqual(DailyTrendProfile.yesterday(from: c.date(from: DateComponents(year: 2023, month: 3, day: 12, hour: 12))!, calendar: c), expected)
        var broken = Calendar(identifier: .gregorian)
        broken.timeZone = TimeZone(identifier: "America/New_York")!
        broken.firstWeekday = 1
        XCTAssertNil(DailyTrendProfile.yesterday(from: expected, calendar: broken))
    }

    func testFutureSamplesAreExcludedFromRunsAndTodayValue() {
        let end = Date(timeIntervalSince1970: 100 * 86_400 + 3600)
        func point(_ day: Int, _ value: Double) -> TrendPoint {
            TrendPoint(recordedAt: utc.date(byAdding: .day, value: day, to: utc.startOfDay(for: end))!, value: value)
        }
        // +1 天是未来样本：不得进入分段，也不得成为当日值。
        let profile = DailyTrendProfile(points: [point(-1, 10), point(0, 20), point(1, 999)], end: end, calendar: utc)
        XCTAssertEqual(profile.todayValue, 20)
        XCTAssertEqual(profile.runs(days: 7).map(\.count), [2])
        XCTAssertEqual(profile.runs(days: 7).flatMap { $0 }.map(\.value), [10, 20])
    }

    func testFutureOnlySamplesYieldNoRunsAndNoTodayValue() {
        let end = Date(timeIntervalSince1970: 100 * 86_400 + 3600)
        func point(_ day: Int, _ value: Double) -> TrendPoint {
            TrendPoint(recordedAt: utc.date(byAdding: .day, value: day, to: utc.startOfDay(for: end))!, value: value)
        }
        let profile = DailyTrendProfile(points: [point(1, 999), point(2, 888)], end: end, calendar: utc)
        XCTAssertNil(profile.todayValue)
        XCTAssertTrue(profile.runs(days: 7).isEmpty)
        XCTAssertTrue(profile.runs(days: 90).isEmpty)
    }
}
