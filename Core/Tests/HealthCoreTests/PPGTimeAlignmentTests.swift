import XCTest
@testable import HealthCore

final class PPGTimeAlignmentTests: XCTestCase {
    func testPointsAndRangesCompareAgainstBothAcquisitionEdges() {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let end = start.addingTimeInterval(12)
        let acquisition = start...end
        let old = start.addingTimeInterval(-60)
        let later = end.addingTimeInterval(30)
        XCTAssertEqual(PPGTimeAlignment.compare(sample: old...old, acquisition: acquisition), .before(seconds: 60))
        XCTAssertEqual(PPGTimeAlignment.compare(sample: later...later, acquisition: acquisition), .after(seconds: 30))
        for sample in [start...start, end...end, old...end, start...later, old...later] {
            XCTAssertEqual(PPGTimeAlignment.compare(sample: sample, acquisition: acquisition), .overlaps)
        }
    }
}
