import XCTest
@testable import HealthCore

final class ECGResearchMeasurementTests: XCTestCase {
    func testSignedAmplitudesAcrossOriginalSamplesAndSkippedDisplayPoints() throws {
        let points = [0.01, 0.75, 0, 1.2, -0.1, -0.4].enumerated().map {
            ECGVoltagePoint(seconds: Double($0.offset) * 0.02, millivolts: $0.element)
        }
        let trace = try ECGWaveform(samples: points, samplingFrequency: 50, displayBudget: 2)
        let beat = try XCTUnwrap(ECGAnnotatedMorphology(trace: trace, reference: 0...2, jPoint: 3, stCursor: 4, tPeak: 5))
        XCTAssertEqual(beat.stChangeMillivolts, -0.11, accuracy: 1e-9)
        XCTAssertEqual(beat.tPeakChangeMillivolts, -0.41, accuracy: 1e-9)
        XCTAssertEqual(beat.stDelayMilliseconds, 20, accuracy: 1e-9)
        let ruler = try XCTUnwrap(ECGCaliper(trace: trace, startIndex: 3, endIndex: 5))
        XCTAssertEqual(ruler.elapsedMilliseconds, 40, accuracy: 1e-9)
        XCTAssertEqual(ruler.voltageChangeMillivolts, -1.6, accuracy: 1e-9)
        XCTAssertNil(ECGAnnotatedMorphology(trace: trace, reference: 0...2, jPoint: 3, stCursor: 5, tPeak: 4))
    }

    func testRejectsGapAndInvalidCursorEvenWhenOverviewEmpty() throws {
        let points = [0.0, 0.01, 0.02, 3, 3.01, 3.02].map { ECGVoltagePoint(seconds: $0, millivolts: 0) }
        let trace = try ECGWaveform(samples: points, samplingFrequency: 100, displayBudget: 0)
        XCTAssertNil(ECGCaliper(trace: trace, startIndex: 2, endIndex: 3))
        XCTAssertNil(ECGCaliper(trace: trace, startIndex: -1, endIndex: 2))
        XCTAssertNil(ECGAnnotatedMorphology(trace: trace, reference: 0...2, jPoint: 3, stCursor: 4, tPeak: 5))
        let summary = ECGSummary(id: UUID(), recordedAt: Date(), classification: "未分类", averageHeartRate: nil)
        let report = summary.experimentalReport(trace: trace, timeZone: .gmt)
        XCTAssertTrue(report.contains("未生成 RR 测量"))
        XCTAssertTrue(report.contains("系统分类　未分类"))
        XCTAssertFalse(report.contains("间期中位数"))
    }
}
