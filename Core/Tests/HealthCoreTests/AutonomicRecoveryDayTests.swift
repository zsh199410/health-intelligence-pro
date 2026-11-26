import XCTest
@testable import HealthCore

final class AutonomicRecoveryDayTests: XCTestCase {
    private var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .gmt
        return calendar
    }
    private let day = Date(timeIntervalSince1970: 86_400 * 100)
    private func point(_ days: Int, _ hour: Int, _ value: Double, minutes: Int = 0) -> TrendPoint {
        TrendPoint(recordedAt: day.addingTimeInterval(Double(days * 86400 + hour * 3600 + minutes * 60)), value: value)
    }

    func testDailyConcordanceAndHourlyCoveragePreserveSampleTimes() throws {
        let sdnn = (-7 ... -1).map { point($0, 8, 50) } + [point(0, 8, 30)]
        let bpm = (-7 ... -1).map { point($0, 6, 60) } + [point(0, 6, 76)]
        let result = AutonomicRecoveryDay(restingSDNN: sdnn, restingBPM: bpm, asOf: point(0, 11, 1).recordedAt, calendar: utc)
        XCTAssertEqual(result.pattern, .higherStrain)
        XCTAssertEqual(result.hours.count, 12)
        XCTAssertEqual(result.observedHours, 1)
        XCTAssertEqual(result.comparableHours, 1)
        XCTAssertEqual(result.hours[8].restingSDNN?.lastSample, sdnn.last?.recordedAt)
        XCTAssertEqual(result.dailyRestingBPM?.lastSample, bpm.last?.recordedAt)
        XCTAssertEqual(result.observedHourFraction, 1.0 / 12, accuracy: 1e-12)
        XCTAssertNil(result.hours[9].restingSDNN)
    }

    func testNoLookaheadCrossHourBorrowingOrDuplicateWeighting() throws {
        let morning = (-6 ... -1).map { point($0, 8, 40) }
        let late = (-20 ... -1).map { point($0, 10, 90) } + [point(-7, 8, 900, minutes: 55)]
        let sample = point(0, 8, 35)
        let input = morning + late + [sample, sample, point(0, 8, 33, minutes: 1), point(0, 8, 77, minutes: 1),
                                      point(0, 8, .nan, minutes: 2), point(0, 8, 0, minutes: 3), point(0, 9, 45)]
        let result = AutonomicRecoveryDay(restingSDNN: input.reversed(), restingBPM: [],
                                           asOf: point(0, 8, 1, minutes: 5).recordedAt, calendar: utc)
        XCTAssertEqual(result.dailySDNN?.sampleCount, 1)
        XCTAssertEqual(result.hours[8].restingSDNN?.referenceDays, 6)
        XCTAssertNil(result.hours[8].restingSDNN?.baselineMedian)
        XCTAssertNil(result.dailySDNN?.baselineMedian)
        XCTAssertEqual(result.pattern, .insufficient)
        let tomorrow = AutonomicRecoveryDay(restingSDNN: input, restingBPM: [], asOf: point(1, 8, 1).recordedAt, calendar: utc)
        XCTAssertNil(tomorrow.dailySDNN)
    }

    func testDSTCoverageCountsRealHoursIncludingRepeatedHour() throws {
        var calendar = utc
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "America/New_York"))
        for (month, date, expected) in [(3, 8, 23), (11, 1, 25)] {
            let end = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: month, day: date, hour: 23, minute: 59)))
            let result = AutonomicRecoveryDay(restingSDNN: [], restingBPM: [], asOf: end, calendar: calendar)
            XCTAssertEqual(result.hours.count, expected)
            XCTAssertEqual(Set(result.hours.map(\.start)).count, expected)
        }
    }
}
