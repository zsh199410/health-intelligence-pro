import XCTest
@testable import HealthCore

/// Unit tests for `StressCalculator`, the self-developed physiological
/// load-signal estimate behind the V3 stress page. No HealthKit, no
/// device data, no fabricated health values: every input is constructed
/// here from a fixed base date. Thresholds are the auditable rules in
/// `StressCalculator.swift`: HRV 15%, resting heart rate 7%, resting
/// heart rate +15 bpm, respiratory rate 20 breaths/min.
/// P0-3: resting heart rate is a day-level value, never copied into hourly
/// samples; it expires 24 hours after it was recorded; confidence is capped
/// (high needs a full dual baseline and at least two contributing signals).
final class StressCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)
    /// Evaluation time: one hour after `base`. A resting heart rate recorded
    /// at `base` is one hour old here, inside the 24-hour validity window.
    private let now = Date(timeIntervalSince1970: 1_700_000_000 + 3600)

    private func hour(_ offsetHours: Int, hrv: Double? = nil,
                      heartRate: Double? = nil, respiratory: Double? = nil,
                      steps: Double? = nil, energy: Double? = nil) -> StressHourInput {
        return StressHourInput(
            hourStart: base.addingTimeInterval(TimeInterval(offsetHours * 3600)),
            hrvMedian: hrv, heartRateMedian: heartRate,
            respiratoryRateMedian: respiratory, steps: steps, activeEnergyKcal: energy
        )
    }

    /// Three resting hours with HRV low and a normal resting heart rate:
    /// two drivers (low HRV + high resting heart rate), elevated. The day's
    /// resting heart rate (60) is a day-level value, passed separately to
    /// `estimate` by `elevatedEstimate`, never stored in the hours.
    private func elevatedHours() -> [StressHourInput] {
        return [
            hour(0, hrv: 35, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, heartRate: 68, respiratory: 15),
            hour(2, hrv: 34, heartRate: 71, respiratory: 14)
        ]
    }

    /// `elevatedHours` + the day's resting heart rate 60 (recorded at
    /// `base`, evaluated at `now`, inside the 24-hour validity window).
    private func elevatedEstimate(hrvBaseline: Double?, restingBaseline: Double?) -> StressEstimate {
        StressCalculator.estimate(hours: elevatedHours(), hrvBaseline: hrvBaseline, restingBaseline: restingBaseline, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
    }

    // MARK: - Insufficient data

    func testEmptyInputIsInsufficient() {
        let estimate = StressCalculator.estimate(hours: [], hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 0)
        XCTAssertEqual(estimate.totalInputs, 4)
        XCTAssertFalse(estimate.drivers.isEmpty)
    }

    func testSingleSampleIsInsufficient() {
        let hours = [hour(0, hrv: 40)]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 1)
    }

    func testOnlyHeartRateAndRespiratoryIsInsufficient() {
        let hours = [
            hour(0, heartRate: 72, respiratory: 14),
            hour(1, heartRate: 75, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 2)
    }

    func testNoHRVHoursAndNoRestingHeartRateIsInsufficient() {
        let hours = [
            hour(0, heartRate: 72, respiratory: 14, steps: 500, energy: 80),
            hour(1, heartRate: 75, respiratory: 15, steps: 600, energy: 90)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: nil, restingBaseline: nil)
        XCTAssertEqual(estimate.level, .insufficient)
    }

    func testRestingHeartRateWithoutHRVIsNotInsufficient() {
        let hours = [
            hour(0, heartRate: 70, respiratory: 14),
            hour(1, heartRate: 68, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: nil, restingBaseline: 55, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertNotEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 3)
    }

    // MARK: - Daily levels

    func testLowHRVAndHighRestingHeartRateIsElevated() {
        let estimate = elevatedEstimate(hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .elevated)
        XCTAssertEqual(estimate.points, 2)
        XCTAssertEqual(estimate.confidence, .high)
        XCTAssertTrue(estimate.hasBaseline)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("HRV") })
        XCTAssertTrue(estimate.drivers.contains { $0.contains("静息心率") })
    }

    func testSameElevationDuringActivityIsNotElevated() {
        // Intent: the SAME heart-rate elevation that scores +1 at rest
        // scores +0 during activity. Baselines are neutral here (HRV and
        // resting heart rate equal their baselines) so the only possible
        // driver is the activity-explained elevation itself.
        // Previous inputs also had low HRV (-30%) and high resting heart
        // rate (+9%), two baseline drivers worth +2 on their own; the test
        // wrongly expected activity to cancel them. Fixed 2026-11-19 after
        // CI #80 proved the implementation follows the documented rules.
        let hours = [
            hour(0, hrv: 50, heartRate: 120, respiratory: 14, steps: 800, energy: 120),
            hour(1, hrv: 50, heartRate: 118, respiratory: 15, steps: 900, energy: 130),
            hour(2, hrv: 50, heartRate: 122, respiratory: 14, steps: 750, energy: 110)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("活动可解释") })
        XCTAssertFalse(estimate.drivers.contains { $0.contains("HRV 低于个人基线") })
        XCTAssertFalse(estimate.drivers.contains { $0.contains("静息心率高于个人基线") })
    }

    func testHighHRVIsLow() {
        let hours = [
            hour(0, hrv: 65, heartRate: 60, respiratory: 14),
            hour(1, hrv: 66, heartRate: 62, respiratory: 13),
            hour(2, hrv: 64, heartRate: 61, respiratory: 14)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .low)
        XCTAssertEqual(estimate.points, -1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("HRV 高于个人基线") })
    }

    func testRestingHeartRateElevationDrivesPoints() {
        // Explicit low activity: the hours are known resting hours.
        let hours = [
            hour(0, hrv: 50, heartRate: 85, respiratory: 14, steps: 10, energy: 5),
            hour(1, hrv: 50, heartRate: 84, respiratory: 15, steps: 20, energy: 8)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 60, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("静息时段心率") })
    }

    func testRespiratoryRateAddsDriver() {
        let hours = [
            hour(0, hrv: 50, heartRate: 68, respiratory: 22),
            hour(1, hrv: 50, heartRate: 70, respiratory: 21)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("呼吸频率高于 20 次/分") })
    }

    // MARK: - Baselines and confidence

    func testNoBaselineCapsConfidenceAtMedium() {
        let hours = [
            hour(0, hrv: 35, heartRate: 85, respiratory: 22, steps: 10, energy: 5),
            hour(1, hrv: 36, heartRate: 84, respiratory: 21, steps: 20, energy: 8)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: nil, restingBaseline: nil, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .elevated)
        XCTAssertEqual(estimate.confidence, .medium)
        XCTAssertFalse(estimate.hasBaseline)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("无个人基线") })
    }

    func testPartialBaselineIsNotFullBaseline() {
        let estimate = elevatedEstimate(hrvBaseline: 50, restingBaseline: nil)
        XCTAssertFalse(estimate.hasBaseline)
        XCTAssertEqual(estimate.confidence, .medium)
    }

    // MARK: - Threshold boundaries (exactly at the threshold does not trigger)

    func testExactlyFifteenPercentHRVDropDoesNotTrigger() {
        // 基线 100、HRV 85：变化量恰好是 double 的 -0.15，不触发。
        let hours = [
            hour(0, hrv: 85, heartRate: 68, respiratory: 14),
            hour(1, hrv: 85, heartRate: 70, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 100, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("HRV 低于个人基线") })
    }

    func testExactlySevenPercentRestingRiseDoesNotTrigger() {
        // 基线 100、静息心率 107：变化量恰好是 double 的 0.07，不触发。
        let hours = [
            hour(0, hrv: 50, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, heartRate: 70, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 100, restingHeartRate: 107, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("静息心率高于个人基线") })
    }

    func testExactlyTwentyBreathsPerMinuteDoesNotTrigger() {
        let hours = [
            hour(0, hrv: 50, heartRate: 68, respiratory: 20),
            hour(1, hrv: 50, heartRate: 70, respiratory: 20)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("呼吸频率高于 20 次/分") })
    }

    // MARK: - Hourly levels

    func testHourlyGapIsNil() {
        let hours = [
            hour(0, hrv: 50, heartRate: 68, respiratory: 14),
            hour(2, hrv: 50, heartRate: 70, respiratory: 14)
        ]
        let levels = StressCalculator.hourlyLevels(hours: hours)
        XCTAssertEqual(levels.count, 2)
        XCTAssertEqual(levels[0].hourStart, hours[0].hourStart)
        XCTAssertEqual(levels[1].hourStart, hours[1].hourStart)
        XCTAssertNotNil(levels[0].level)
        XCTAssertNotNil(levels[1].level)
    }

    func testHourlyLevelsAreSortedByHour() {
        let hours = [
            hour(5, hrv: 50, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, heartRate: 70, respiratory: 14)
        ]
        let levels = StressCalculator.hourlyLevels(hours: hours)
        XCTAssertLessThan(levels[0].hourStart, levels[1].hourStart)
    }

    func testHourlyLevelWithNoPhysiologicalInputIsNil() {
        let hours = [hour(0, steps: 500, energy: 80)]
        let levels = StressCalculator.hourlyLevels(hours: hours)
        XCTAssertEqual(levels.count, 1)
        XCTAssertNil(levels[0].level)
    }

    func testHourlyElevatedNeedsTwoDrivers() {
        let hours = [
            hour(0, heartRate: 85, respiratory: 22, steps: 10, energy: 5),
            hour(1, heartRate: 70, respiratory: 14, steps: 10, energy: 5)
        ]
        let levels = StressCalculator.hourlyLevels(hours: hours, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(levels[0].level, .elevated)
        XCTAssertEqual(levels[1].level, .moderate)
    }

    // MARK: - Unknown activity is never assumed resting (Build 26 fix)

    func testUnknownActivityIsNotAssumedResting() {
        // Same elevation as testRestingHeartRateElevationDrivesPoints, but
        // with no step/energy samples: the elevation is neither a resting
        // driver nor explained by activity.
        let hours = [
            hour(0, hrv: 50, heartRate: 85, respiratory: 14),
            hour(1, hrv: 50, heartRate: 84, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 60, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("静息时段心率") })
        XCTAssertFalse(estimate.drivers.contains { $0.contains("活动可解释") })
    }

    func testExplicitLowActivityIsResting() {
        let input = hour(0, heartRate: 70, steps: 10, energy: 5)
        XCTAssertTrue(input.isRestingHour)
        XCTAssertFalse(input.isActiveHour)
    }

    func testUnknownActivityIsNeitherRestingNorActive() {
        let input = hour(0, heartRate: 70)
        XCTAssertFalse(input.isRestingHour)
        XCTAssertFalse(input.isActiveHour)
    }

    func testHighStepsIsActiveNotResting() {
        let input = hour(0, heartRate: 70, steps: 500, energy: 80)
        XCTAssertFalse(input.isRestingHour)
        XCTAssertTrue(input.isActiveHour)
    }

    // MARK: - Drivers are never empty for a decided level

    func testDriversAreNonEmptyForEveryDecidedLevel() {
        let low = StressCalculator.estimate(hours: [
            hour(0, hrv: 65, heartRate: 60, respiratory: 14),
            hour(1, hrv: 66, heartRate: 62, respiratory: 13)
        ], hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(low.level, .low)
        XCTAssertFalse(low.drivers.isEmpty)

        let moderate = StressCalculator.estimate(hours: [
            hour(0, hrv: 50, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, heartRate: 70, respiratory: 15)
        ], hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(moderate.level, .moderate)
        XCTAssertFalse(moderate.drivers.isEmpty)

        let elevated = elevatedEstimate(hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(elevated.level, .elevated)
        XCTAssertFalse(elevated.drivers.isEmpty)
    }

    // MARK: - P0-3: day-level resting heart rate, expiry, confidence cap

    func testStepsOnlyHourWithDailyRestingHeartRateIsNil() {
        // P0-3: the day's resting heart rate is no longer copied into hourly
        // samples, so an hour with only steps / energy is nil even when the
        // day has a resting heart rate.
        let hours = [hour(0, steps: 500, energy: 80)]
        let levels = StressCalculator.hourlyLevels(hours: hours, restingHeartRate: 60, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(levels.count, 1)
        XCTAssertNil(levels[0].level)
    }

    func testExpiredRestingHeartRateIsInsufficient() {
        // P0-3: a resting heart rate recorded 25 hours ago is expired: the
        // baseline is unusable, the level is insufficient and confidence is
        // at most medium, even though HRV / heart rate / respiratory rate
        // are otherwise present.
        let hours = [
            hour(0, hrv: 35, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, heartRate: 68, respiratory: 15)
        ]
        let recordedAt = base.addingTimeInterval(-25 * 3600)
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 60, restingHeartRateRecordedAt: recordedAt, now: base)
        XCTAssertEqual(estimate.level, .insufficient)
        XCTAssertNotEqual(estimate.confidence, .high)
        XCTAssertFalse(estimate.hasBaseline)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("超过 24 小时") })
    }

    func testFreshRestingHeartRateWithin24HoursIsUsed() {
        // Recorded 23 hours ago: still valid, counted as a covered input and
        // compared against the baseline.
        let hours = [
            hour(0, hrv: 35, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, heartRate: 68, respiratory: 15)
        ]
        let recordedAt = base.addingTimeInterval(-23 * 3600)
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 60, restingHeartRateRecordedAt: recordedAt, now: base)
        XCTAssertNotEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 4)
        XCTAssertEqual(estimate.confidence, .high)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("静息心率高于个人基线") })
    }

    func testExactly24HoursOldRestingHeartRateIsStillFresh() {
        // Exactly 24 hours old is still valid (only strictly over 24 hours expires).
        let hours = [
            hour(0, hrv: 35, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, heartRate: 68, respiratory: 15)
        ]
        let recordedAt = base.addingTimeInterval(-24 * 3600)
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 60, restingHeartRateRecordedAt: recordedAt, now: base)
        XCTAssertNotEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 4)
    }

    func testSingleDriverNeverGivesHighConfidence() {
        // P0-3: full dual baseline and 4 covered inputs, but only one signal
        // (high HRV) drives the score: confidence is at most medium.
        let hours = [
            hour(0, hrv: 65, heartRate: 60, respiratory: 14),
            hour(1, hrv: 66, heartRate: 62, respiratory: 13)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55, restingHeartRate: 55, restingHeartRateRecordedAt: base, now: now)
        XCTAssertEqual(estimate.level, .low)
        XCTAssertEqual(estimate.confidence, .medium)
    }

    func testHourlyRestingElevationNeedsFreshRestingHeartRate() {
        // P0-3: an expired resting heart rate is not used as the reference
        // for the resting-hour heart-rate rule, so only the respiratory-rate
        // driver fires and the hour is moderate, not elevated.
        let hours = [hour(0, heartRate: 85, respiratory: 22, steps: 10, energy: 5)]
        let recordedAt = base.addingTimeInterval(-25 * 3600)
        let levels = StressCalculator.hourlyLevels(hours: hours, restingHeartRate: 60, restingHeartRateRecordedAt: recordedAt, now: base)
        XCTAssertEqual(levels.count, 1)
        XCTAssertEqual(levels[0].level, .moderate)
    }

    func testMissingRestingHeartRateIsNotExpired() {
        // Missing (never supplied) is not expired: with HRV, heart rate and
        // respiratory rate present the estimate is decided, not insufficient.
        let hours = [
            hour(0, hrv: 35, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, heartRate: 68, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertNotEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 3)
    }
}
