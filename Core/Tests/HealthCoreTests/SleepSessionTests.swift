import XCTest
@testable import HealthCore

final class SleepSessionTests: XCTestCase {
    private func interval(_ startOffset: TimeInterval, _ endOffset: TimeInterval, stage: SleepStage = .core) -> SleepInterval {
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return SleepInterval(start: base.addingTimeInterval(startOffset),
                             end: base.addingTimeInterval(endOffset), stage: stage)
    }

    func testEmptyIntervalsHaveNoWindow() {
        XCTAssertNil(SleepSession.window(from: []))
    }

    func testSingleIntervalIsItsOwnWindow() {
        let only = interval(0, 3_600)
        XCTAssertEqual(SleepSession.window(from: [only]), only.start...only.end)
    }

    func testContiguousNightSpansMidnight() {
        // 22:00 -> 06:00 across midnight, with a brief awakening inside.
        let intervals = [
            interval(0, 7_200, stage: .core),
            interval(7_200, 25_200, stage: .deep),
            interval(25_200, 25_800, stage: .awake),
            interval(25_800, 28_800, stage: .core)
        ]
        let window = SleepSession.window(from: intervals)
        XCTAssertEqual(window?.lowerBound, intervals.first!.start)
        XCTAssertEqual(window?.upperBound, intervals.last!.end)
    }

    func testTwoNightsSplitByLongGapKeepsOnlyLatest() {
        let previousNight = [interval(-100_000, -97_000), interval(-97_000, -75_000)]
        let latestNight = [interval(0, 7_200), interval(7_200, 28_800)]
        let window = SleepSession.window(from: previousNight + latestNight)
        XCTAssertEqual(window?.lowerBound, latestNight.first!.start)
        XCTAssertEqual(window?.upperBound, latestNight.last!.end)
    }

    func testShortGapStaysInSameSession() {
        let intervals = [interval(0, 3_600), interval(3_600 + 3_000, 7_200)]
        XCTAssertEqual(SleepSession.window(from: intervals)?.lowerBound, intervals.first!.start)
    }

    func testOverlappingIntervalsFromTwoSourcesJoin() {
        let intervals = [interval(0, 3_600, stage: .rem), interval(1_800, 3_600, stage: .rem)]
        let window = SleepSession.window(from: intervals)
        XCTAssertEqual(window?.lowerBound, intervals.first!.start)
        XCTAssertEqual(window?.upperBound, intervals[0].end)
    }

    func testOverlappingEarlierSampleCanEndAfterLastStartingSample() {
        let longSource = interval(0, 8 * 3_600, stage: .core)
        let shortSource = interval(7 * 3_600, 7 * 3_600 + 300, stage: .rem)
        let window = SleepSession.window(from: [longSource, shortSource])
        XCTAssertEqual(window, longSource.start...longSource.end)
        XCTAssertEqual(SleepSession.latestIntervals(from: [longSource, shortSource]).count, 2)
    }

    func testLongSourceBridgesShortSamplesAcrossApparentGap() {
        let longSource = interval(0, 10 * 3_600)
        let middle = interval(1 * 3_600, 2 * 3_600)
        let final = interval(9 * 3_600, 11 * 3_600)
        let window = SleepSession.window(from: [longSource, middle, final])
        XCTAssertEqual(window, longSource.start...final.end)
    }

    func testLatestIntervalsExcludePreviousNightFromDuration() {
        let previous = interval(-100_000, -75_000, stage: .core)
        let latest = interval(0, 6 * 3_600, stage: .deep)
        let all = [previous, latest]
        let selected = SleepSession.latestIntervals(from: all)
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.start, latest.start)
        XCTAssertEqual(SleepCalculator.summarize(selected).totalAsleepMinutes, 360)
        XCTAssertEqual(SleepSession.window(from: all), latest.start...latest.end)
    }

    func testLatestIntervalsKeepOverlappingSourcesForDeduplication() {
        let first = interval(0, 3_600, stage: .core)
        let overlapping = interval(1_800, 3_600, stage: .core)
        let selected = SleepSession.latestIntervals(from: [first, overlapping])
        XCTAssertEqual(selected.count, 2)
        XCTAssertEqual(SleepCalculator.summarize(selected).totalAsleepMinutes, 60)
    }

    func testLatestIntervalsRejectInvalidAndEmptyInputs() {
        let invalid = interval(4_000, 1_000)
        XCTAssertTrue(SleepSession.latestIntervals(from: [invalid]).isEmpty)
        XCTAssertTrue(SleepSession.latestIntervals(from: []).isEmpty)
    }

    func testInvalidIntervalsAreIgnored() {
        let bad = SleepInterval(start: Date(timeIntervalSince1970: 1_700_003_600),
                                end: Date(timeIntervalSince1970: 1_700_000_000), stage: .core)
        XCTAssertNil(SleepSession.window(from: [bad]))
    }
}
