import XCTest
@testable import HealthCore

/// Unit tests for `SleepCalculator.segments`, the deduplicated
/// time-ordered stage pieces behind the V3 sleep stage timeline.
/// Covers the five cases from GPT's risk review of main commit 5468011:
/// cross-midnight, overlapping data, stage priority, empty records,
/// and summary-minutes consistency. No HealthKit, no device data.
final class SleepCalculatorSegmentsTests: XCTestCase {
    private func interval(_ startOffset: TimeInterval, _ endOffset: TimeInterval, stage: SleepStage) -> SleepInterval {
        // Base is 2023-11-14 22:13:20 UTC, so a 0 -> 28_800 span crosses midnight.
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return SleepInterval(start: base.addingTimeInterval(startOffset),
                             end: base.addingTimeInterval(endOffset), stage: stage)
    }

    // MARK: - Empty records

    func testEmptyInputReturnsEmpty() {
        XCTAssertTrue(SleepCalculator.segments([]).isEmpty)
    }

    func testInvalidIntervalsAreIgnored() {
        let bad = SleepInterval(start: Date(timeIntervalSince1970: 1_700_003_600),
                                end: Date(timeIntervalSince1970: 1_700_000_000), stage: .core)
        XCTAssertTrue(SleepCalculator.segments([bad]).isEmpty)
    }

    // MARK: - Cross-midnight

    func testNightSpanningMidnightKeepsFullSpan() {
        let intervals = [
            interval(0, 7_200, stage: .core),
            interval(7_200, 18_000, stage: .deep),
            interval(18_000, 28_800, stage: .rem)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments.first?.start, intervals.first?.start)
        XCTAssertEqual(segments.last?.end, intervals.last?.end)
        let total = segments.reduce(0) { $0 + $1.end.timeIntervalSince($1.start) }
        XCTAssertEqual(total, 28_800, accuracy: 0.001)
        // The span really does cross midnight (UTC): start and end fall on different days.
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(secondsFromGMT: 0)!
        XCTAssertNotEqual(utc.component(.day, from: segments.first!.start),
                          utc.component(.day, from: segments.last!.end))
    }

    // MARK: - Overlapping data

    func testOverlappingIntervalsDeduplicateToUnion() {
        let intervals = [
            interval(0, 3_600, stage: .core),
            interval(1_800, 5_400, stage: .core)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.start, intervals.first?.start)
        XCTAssertEqual(segments.first?.end, intervals.last?.end)
    }

    func testAdjacentSameStageMerges() {
        let intervals = [
            interval(0, 1_800, stage: .core),
            interval(1_800, 3_600, stage: .core)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.start, intervals.first?.start)
        XCTAssertEqual(segments.first?.end, intervals.last?.end)
    }

    func testSegmentsAreOrderedAndNonOverlapping() {
        let intervals = [
            interval(3_600, 7_200, stage: .rem),
            interval(0, 3_600, stage: .core),
            interval(1_800, 5_400, stage: .deep)
        ]
        let segments = SleepCalculator.segments(intervals)
        for i in 1..<segments.count {
            XCTAssertLessThanOrEqual(segments[i - 1].end, segments[i].start)
            XCTAssertLessThan(segments[i - 1].start, segments[i].start)
        }
    }

    // MARK: - Stage priority (awake > deep > REM > core > unspecified)

    func testConflictingStagesFollowPriority() {
        let intervals = [
            interval(0, 3_600, stage: .core),
            interval(1_800, 3_600, stage: .deep),
            interval(3_000, 3_600, stage: .awake)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 3)
        XCTAssertEqual(segments[0].stage, .core)
        XCTAssertEqual(segments[1].stage, .deep)
        XCTAssertEqual(segments[2].stage, .awake)
        XCTAssertEqual(segments[0].end, segments[1].start)
        XCTAssertEqual(segments[1].end, segments[2].start)
    }

    func testUnspecifiedLosesToCore() {
        let intervals = [
            interval(0, 3_600, stage: .unspecified),
            interval(0, 3_600, stage: .core)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.stage, .core)
    }

    func testDeepLosesToAwake() {
        let intervals = [
            interval(0, 3_600, stage: .deep),
            interval(0, 3_600, stage: .awake)
        ]
        let segments = SleepCalculator.segments(intervals)
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?.stage, .awake)
    }

    // MARK: - Summary-minutes consistency

    func testSegmentMinutesMatchSummary() {
        let intervals = [
            interval(0, 3_600, stage: .core),
            interval(3_600, 5_400, stage: .deep),
            interval(5_400, 7_200, stage: .rem),
            interval(7_200, 7_800, stage: .awake),
            interval(1_800, 5_400, stage: .core)
        ]
        let segments = SleepCalculator.segments(intervals)
        let summary = SleepCalculator.summarize(intervals)
        // Sum seconds per stage first, then round — same as summarize.
        var secondsByStage: [SleepStage: TimeInterval] = [:]
        for segment in segments {
            secondsByStage[segment.stage, default: 0] += segment.end.timeIntervalSince(segment.start)
        }
        for stage in SleepStage.allCases {
            let mins = Int(((secondsByStage[stage] ?? 0) / 60).rounded())
            XCTAssertEqual(mins, summary.minutesByStage[stage] ?? 0,
                           "minutes for \(stage.rawValue) differ between segments and summary")
        }
        let asleepFromSegments = [SleepStage.deep, .rem, .core, .unspecified]
            .reduce(0) { $0 + Int(((secondsByStage[$1] ?? 0) / 60).rounded()) }
        XCTAssertEqual(asleepFromSegments, summary.totalAsleepMinutes)
        XCTAssertEqual(Int(((secondsByStage[.awake] ?? 0) / 60).rounded()), summary.minutesAwake)
    }
}
