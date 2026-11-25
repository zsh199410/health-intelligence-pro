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

    func testYesterdayMatchesDurationAcrossDSTOrRejectsImpossibleWindow() {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/New_York")!
        let noon = c.date(from: DateComponents(year: 2025, month: 3, day: 10, hour: 12))!
        let yesterday = DailyTrendProfile.previousCutoff(end: noon, calendar: c)!
        XCTAssertEqual(yesterday.timeIntervalSince(c.startOfDay(for: yesterday)), 12 * 3600)
        let late = c.date(byAdding: .hour, value: 11, to: noon)!
        XCTAssertNil(DailyTrendProfile.previousCutoff(end: late, calendar: c))
        XCTAssertNil(DailyTrendProfile.previousCutoff(end: c.startOfDay(for: noon), calendar: c))
    }
}
