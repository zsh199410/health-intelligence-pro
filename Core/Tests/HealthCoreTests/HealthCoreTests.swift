import XCTest
@testable import HealthCore

final class HealthCoreTests: XCTestCase {
    func testSleepDoesNotCountAwakeAsAsleep() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let intervals = [
            SleepInterval(start: now, end: now.addingTimeInterval(3_600), stage: .core),
            SleepInterval(start: now.addingTimeInterval(3_600), end: now.addingTimeInterval(5_400), stage: .deep),
            SleepInterval(start: now.addingTimeInterval(5_400), end: now.addingTimeInterval(6_000), stage: .awake)
        ]
        let result = SleepCalculator.summarize(intervals)
        XCTAssertEqual(result.totalAsleepMinutes, 90)
        XCTAssertEqual(result.minutesAwake, 10)
    }

    func testDuplicatedStageIntervalsMerge() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let intervals = [
            SleepInterval(start: now, end: now.addingTimeInterval(3_600), stage: .rem),
            SleepInterval(start: now.addingTimeInterval(1_800), end: now.addingTimeInterval(3_600), stage: .rem)
        ]
        XCTAssertEqual(SleepCalculator.summarize(intervals).totalAsleepMinutes, 60)
    }

    func testNoInsightsPretendToHaveMeasurements() {
        let insights = InsightEngine.insights(readings: [:], sleep: nil)
        XCTAssertEqual(insights.count, 1)
        XCTAssertEqual(insights[0].id, "empty")
    }

    func testInsightIncludesActualReading() {
        let record = MetricReading(id: "restingHeartRate", value: 61, unit: "次/分", recordedAt: .now, source: "HealthKit")
        let insights = InsightEngine.insights(readings: ["restingHeartRate": record], sleep: nil)
        XCTAssertTrue(insights.first?.body.contains("61.0") == true)
    }
}

extension HealthCoreTests {
    func testCrossStageOverlapNotDoubleCounted() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let intervals = [
            SleepInterval(start: start, end: start.addingTimeInterval(3600), stage: .core),
            SleepInterval(start: start.addingTimeInterval(1800), end: start.addingTimeInterval(5400), stage: .rem)
        ]
        let result = SleepCalculator.summarize(intervals)
        XCTAssertEqual(result.totalAsleepMinutes, 90)
        XCTAssertEqual(result.minutesByStage[.core], 30)
        XCTAssertEqual(result.minutesByStage[.rem], 60)
    }

    func testAwakeSupersedesOverlap() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let result = SleepCalculator.summarize([
            SleepInterval(start: start, end: start.addingTimeInterval(3600), stage: .deep),
            SleepInterval(start: start.addingTimeInterval(600), end: start.addingTimeInterval(900), stage: .awake)
        ])
        XCTAssertEqual(result.totalAsleepMinutes, 55)
        XCTAssertEqual(result.minutesAwake, 5)
    }

    func testDenseOverlappingSourcesKeepEntireSessionAndRealGaps() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        func interval(_ a: Int, _ b: Int, _ stage: SleepStage) -> SleepInterval {
            SleepInterval(start: start.addingTimeInterval(Double(a * 60)),
                          end: start.addingTimeInterval(Double(b * 60)), stage: stage)
        }
        let minuteSamples = (0..<480).map { interval($0, $0 + 1, .core) }
        let samples = minuteSamples + minuteSamples + [interval(60, 90, .deep), interval(481, 482, .core)]
        let segments = SleepCalculator.segments(samples.reversed())
        XCTAssertEqual(segments, [
            interval(0, 60, .core), interval(60, 90, .deep), interval(90, 480, .core),
            interval(481, 482, .core)
        ])
        XCTAssertEqual(SleepCalculator.summarize(samples).totalAsleepMinutes, 481)
    }

    func testInvalidAndEmptyIntervals() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let result = SleepCalculator.summarize([
            SleepInterval(start: start, end: start, stage: .rem),
            SleepInterval(start: start.addingTimeInterval(300), end: start, stage: .core)
        ])
        XCTAssertEqual(result.totalAsleepMinutes, 0)
        XCTAssertEqual(result.minutesAwake, 0)
    }
}
