import XCTest
@testable import HealthCore

final class CardiovascularRecoveryCoverageTests: XCTestCase {
    private let timestamp = Date(timeIntervalSince1970: 1_700_000_000)

    private func reading(_ id: String, value: Double) -> MetricReading {
        MetricReading(id: id, value: value, unit: "测试单位",
                      recordedAt: timestamp, source: "Test fixture")
    }

    func testEmptyReadingsDoNotInventRecovery() {
        XCTAssertTrue(CardiovascularRecoveryCoverage.availableMetricIDs(in: [:]).isEmpty)
        XCTAssertNil(CardiovascularRecoveryCoverage.oneMinuteRecovery(in: [:]))
    }

    func testOnlySupportedMetricsContributeToCoverage() {
        let readings = [
            "heartRate": reading("heartRate", value: 65),
            "hrv": reading("hrv", value: 42),
            "vo2Max": reading("vo2Max", value: 36)
        ]
        XCTAssertEqual(CardiovascularRecoveryCoverage.availableMetricIDs(in: readings), ["hrv", "vo2Max"])
        XCTAssertNil(CardiovascularRecoveryCoverage.oneMinuteRecovery(in: readings))
    }

    func testNonFiniteOrNegativeMeasurementsAreNotPresented() {
        let readings = [
            "heartRateRecoveryOneMinute": reading("heartRateRecoveryOneMinute", value: .nan),
            "hrv": reading("hrv", value: -.infinity),
            "restingHeartRate": reading("restingHeartRate", value: -1)
        ]
        XCTAssertTrue(CardiovascularRecoveryCoverage.availableMetricIDs(in: readings).isEmpty)
        XCTAssertNil(CardiovascularRecoveryCoverage.oneMinuteRecovery(in: readings))
    }

    func testNegativePostWorkoutChangeIsRetainedRatherThanHidden() {
        // A signed reduction can be below zero if heart rate rises after the workout.
        let sample = reading("heartRateRecoveryOneMinute", value: -5)
        XCTAssertEqual(CardiovascularRecoveryCoverage.oneMinuteRecovery(
            in: ["heartRateRecoveryOneMinute": sample]), sample)
    }

    func testRecordedRecoveryPreservesSourceAndTime() {
        let sample = reading("heartRateRecoveryOneMinute", value: 18)
        let readings = ["heartRateRecoveryOneMinute": sample]
        XCTAssertEqual(CardiovascularRecoveryCoverage.availableMetricIDs(in: readings), ["heartRateRecoveryOneMinute"])
        XCTAssertEqual(CardiovascularRecoveryCoverage.oneMinuteRecovery(in: readings), sample)
    }
}
