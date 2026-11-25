import XCTest
@testable import HealthCore

final class ECGCenterTests: XCTestCase {
    func testZoomRestoresRawDetailAndPreservesGapsAndBounds() throws {
        let raw = [0, 1, 2, 3, 6, 7, 8, 9].map { ECGVoltagePoint(seconds: Double($0), millivolts: Double($0)) }
        let trace = try ECGWaveform(samples: raw, samplingFrequency: 1, displayBudget: 4)
        XCTAssertEqual(trace.segments.flatMap(\.points).count, 4)
        XCTAssertEqual(trace.segments(in: 2...7).map(\.points), [Array(raw[2...3]), Array(raw[4...5])])
        XCTAssertTrue(trace.segments(in: 4...5).isEmpty)
    }

    func testReportUsesRecordTimeZoneClassificationAndActualData() throws {
        let raw = [ECGVoltagePoint(seconds: 2, millivolts: 0), ECGVoltagePoint(seconds: 2.01, millivolts: 0.05)]
        let trace = try ECGWaveform(samples: raw, samplingFrequency: 100)
        let summary = ECGSummary(id: UUID(), recordedAt: Date(timeIntervalSince1970: 0),
                                 classification: "记录质量不足（系统分类）", averageHeartRate: nil, source: "设备 A")
        let result = summary.report(trace: trace, timeZone: try XCTUnwrap(TimeZone(identifier: "Asia/Shanghai")))
        for value in ["设备 A", "08:00:00", "Asia/Shanghai", summary.classification, "100.00 Hz", "0.010 秒"] {
            XCTAssertTrue(result.contains(value))
        }
        XCTAssertFalse(result.contains("平均心率"))
    }
}
