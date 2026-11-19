import XCTest
@testable import HealthCore

/// Unit tests for `StressCalculator`, the self-developed physiological
/// load-signal estimate behind the V3 stress page. No HealthKit, no
/// device data, no fabricated health values: every input is constructed
/// here from a fixed base date. Thresholds are the auditable rules in
/// `StressCalculator.swift`: HRV 15%, resting heart rate 7%, resting
/// heart rate +15 bpm, respiratory rate 20 breaths/min.
final class StressCalculatorTests: XCTestCase {
    private let base = Date(timeIntervalSince1970: 1_700_000_000)

    private func hour(_ offsetHours: Int, hrv: Double? = nil, resting: Double? = nil,
                      heartRate: Double? = nil, respiratory: Double? = nil,
                      steps: Double = 0, energy: Double = 0) -> StressHourInput {
        return StressHourInput(
            hourStart: base.addingTimeInterval(TimeInterval(offsetHours * 3600)),
            hrvMedian: hrv, restingHeartRate: resting, heartRateMedian: heartRate,
            respiratoryRateMedian: respiratory, steps: steps, activeEnergyKcal: energy
        )
    }

    /// Three resting hours with HRV low, resting heart rate high and a
    /// normal resting heart rate: two drivers, elevated.
    private func elevatedHours() -> [StressHourInput] {
        return [
            hour(0, hrv: 35, resting: 60, heartRate: 70, respiratory: 14),
            hour(1, hrv: 36, resting: 60, heartRate: 68, respiratory: 15),
            hour(2, hrv: 34, resting: 60, heartRate: 71, respiratory: 14)
        ]
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
            hour(0, resting: 60, heartRate: 70, respiratory: 14),
            hour(1, resting: 60, heartRate: 68, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: nil, restingBaseline: 55)
        XCTAssertNotEqual(estimate.level, .insufficient)
        XCTAssertEqual(estimate.coveredInputs, 3)
    }

    // MARK: - Daily levels

    func testLowHRVAndHighRestingHeartRateIsElevated() {
        let estimate = StressCalculator.estimate(hours: elevatedHours(), hrvBaseline: 50, restingBaseline: 55)
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
            hour(0, hrv: 50, resting: 55, heartRate: 120, respiratory: 14, steps: 800, energy: 120),
            hour(1, hrv: 50, resting: 55, heartRate: 118, respiratory: 15, steps: 900, energy: 130),
            hour(2, hrv: 50, resting: 55, heartRate: 122, respiratory: 14, steps: 750, energy: 110)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("活动可解释") })
        XCTAssertFalse(estimate.drivers.contains { $0.contains("HRV 低于个人基线") })
        XCTAssertFalse(estimate.drivers.contains { $0.contains("静息心率高于个人基线") })
    }

    func testHighHRVIsLow() {
        let hours = [
            hour(0, hrv: 65, resting: 55, heartRate: 60, respiratory: 14),
            hour(1, hrv: 66, resting: 55, heartRate: 62, respiratory: 13),
            hour(2, hrv: 64, resting: 55, heartRate: 61, respiratory: 14)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .low)
        XCTAssertEqual(estimate.points, -1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("HRV 高于个人基线") })
    }

    func testRestingHeartRateElevationDrivesPoints() {
        let hours = [
            hour(0, hrv: 50, resting: 60, heartRate: 85, respiratory: 14),
            hour(1, hrv: 50, resting: 60, heartRate: 84, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 60)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("静息时段心率") })
    }

    func testRespiratoryRateAddsDriver() {
        let hours = [
            hour(0, hrv: 50, resting: 55, heartRate: 68, respiratory: 22),
            hour(1, hrv: 50, resting: 55, heartRate: 70, respiratory: 21)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertEqual(estimate.points, 1)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("呼吸频率高于 20 次/分") })
    }

    // MARK: - Baselines and confidence

    func testNoBaselineCapsConfidenceAtMedium() {
        let hours = [
            hour(0, hrv: 35, resting: 60, heartRate: 85, respiratory: 22),
            hour(1, hrv: 36, resting: 60, heartRate: 84, respiratory: 21)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: nil, restingBaseline: nil)
        XCTAssertEqual(estimate.level, .elevated)
        XCTAssertEqual(estimate.confidence, .medium)
        XCTAssertFalse(estimate.hasBaseline)
        XCTAssertTrue(estimate.drivers.contains { $0.contains("无个人基线") })
    }

    func testPartialBaselineIsNotFullBaseline() {
        let estimate = StressCalculator.estimate(hours: elevatedHours(), hrvBaseline: 50, restingBaseline: nil)
        XCTAssertFalse(estimate.hasBaseline)
        XCTAssertEqual(estimate.confidence, .medium)
    }

    // MARK: - Threshold boundaries (exactly at the threshold does not trigger)

    func testExactlyFifteenPercentHRVDropDoesNotTrigger() {
        // 基线 100、HRV 85：变化量恰好是 double 的 -0.15，不触发。
        let hours = [
            hour(0, hrv: 85, resting: 55, heartRate: 68, respiratory: 14),
            hour(1, hrv: 85, resting: 55, heartRate: 70, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 100, restingBaseline: 55)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("HRV 低于个人基线") })
    }

    func testExactlySevenPercentRestingRiseDoesNotTrigger() {
        // 基线 100、静息心率 107：变化量恰好是 double 的 0.07，不触发。
        let hours = [
            hour(0, hrv: 50, resting: 107, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, resting: 107, heartRate: 70, respiratory: 15)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 100)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertEqual(estimate.level, .moderate)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("静息心率高于个人基线") })
    }

    func testExactlyTwentyBreathsPerMinuteDoesNotTrigger() {
        let hours = [
            hour(0, hrv: 50, resting: 55, heartRate: 68, respiratory: 20),
            hour(1, hrv: 50, resting: 55, heartRate: 70, respiratory: 20)
        ]
        let estimate = StressCalculator.estimate(hours: hours, hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(estimate.points, 0)
        XCTAssertFalse(estimate.drivers.contains { $0.contains("呼吸频率高于 20 次/分") })
    }

    // MARK: - Hourly levels

    func testHourlyGapIsNil() {
        let hours = [
            hour(0, hrv: 50, resting: 55, heartRate: 68, respiratory: 14),
            hour(2, hrv: 50, resting: 55, heartRate: 70, respiratory: 14)
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
            hour(5, hrv: 50, resting: 55, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, resting: 55, heartRate: 70, respiratory: 14)
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
            hour(0, resting: 60, heartRate: 85, respiratory: 22),
            hour(1, resting: 60, heartRate: 70, respiratory: 14)
        ]
        let levels = StressCalculator.hourlyLevels(hours: hours)
        XCTAssertEqual(levels[0].level, .elevated)
        XCTAssertEqual(levels[1].level, .moderate)
    }

    // MARK: - Drivers are never empty for a decided level

    func testDriversAreNonEmptyForEveryDecidedLevel() {
        let low = StressCalculator.estimate(hours: [
            hour(0, hrv: 65, resting: 55, heartRate: 60, respiratory: 14),
            hour(1, hrv: 66, resting: 55, heartRate: 62, respiratory: 13)
        ], hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(low.level, .low)
        XCTAssertFalse(low.drivers.isEmpty)

        let moderate = StressCalculator.estimate(hours: [
            hour(0, hrv: 50, resting: 55, heartRate: 68, respiratory: 14),
            hour(1, hrv: 50, resting: 55, heartRate: 70, respiratory: 15)
        ], hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(moderate.level, .moderate)
        XCTAssertFalse(moderate.drivers.isEmpty)

        let elevated = StressCalculator.estimate(hours: elevatedHours(), hrvBaseline: 50, restingBaseline: 55)
        XCTAssertEqual(elevated.level, .elevated)
        XCTAssertFalse(elevated.drivers.isEmpty)
    }
}


extension StressCalculatorTests {
    func testMissingActivityDoesNotBecomeRestingOrExplainedActivity() {
        let missing = StressHourInput(hourStart: base, restingHeartRate: 60, heartRateMedian: 90)
        XCTAssertFalse(missing.isRestingHour)
        XCTAssertFalse(missing.hasActivityData)
        let knownRest = hour(0, resting: 60, heartRate: 90, steps: 0, energy: 0)
        XCTAssertTrue(knownRest.isRestingHour)
    }
}
