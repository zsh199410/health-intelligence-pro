import Foundation
import XCTest
@testable import HealthCore

/// Build 28 P0-2: the resting-context filter must drop future samples,
/// conflicting UUIDs and non-Watch / in-workout samples, and the raw
/// history window must span calendar days across a DST transition.
final class SourcedSampleTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func sample(_ value: Double, day: Int, hour: Int, minute: Int = 0,
                        uuid: UUID = UUID(), sourceName: String? = "Apple Watch",
                        deviceModel: String? = "Watch7,4") -> SourcedSample {
        let start = date(day, hour, minute: minute)
        return SourcedSample(value: value, start: start,
                             end: start.addingTimeInterval(5 * 60), uuid: uuid,
                             sourceName: sourceName, sourceBundleID: "com.apple.Health",
                             deviceName: "Apple Watch", deviceManufacturer: "Apple",
                             deviceModel: deviceModel)
    }

    private func workout(day: Int, startHour: Int, endHour: Int) -> DateInterval {
        DateInterval(start: date(day, startHour), end: date(day, endHour))
    }

    func testFutureSamplesAreDropped() {
        let asOf = date(10, 12)
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8), sample(60, day: 10, hour: 13)],
            workouts: [], asOf: asOf, truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50])
        XCTAssertEqual(result.diagnostics.fetchedCount, 2)
        XCTAssertEqual(result.diagnostics.droppedFutureCount, 1)
        XCTAssertEqual(result.diagnostics.keptCount, 1)
    }

    func testConflictingUUIDValuesAreBothDropped() {
        let uuid = UUID()
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8, uuid: uuid), sample(55, day: 9, hour: 9, uuid: uuid)],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.count, 0)
        XCTAssertEqual(result.diagnostics.droppedDuplicateCount, 2)
        XCTAssertEqual(result.diagnostics.keptCount, 0)
    }

    func testIdenticalUUIDDuplicatesCollapseToOne() {
        let uuid = UUID()
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8, uuid: uuid), sample(50, day: 9, hour: 9, uuid: uuid)],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50])
        XCTAssertEqual(result.diagnostics.droppedDuplicateCount, 1)
        XCTAssertEqual(result.diagnostics.keptCount, 1)
    }

    func testLimitTruncationIsFlagged() {
        let result = selectRestingSamples(
            [sample(50, day: 8, hour: 8), sample(52, day: 9, hour: 8), sample(54, day: 9, hour: 9)],
            workouts: [], asOf: date(10, 12), truncated: true)
        XCTAssertTrue(result.diagnostics.truncated)
        XCTAssertEqual(result.samples.count, 3)
    }

    func testNonWatchSourcesAreExcluded() {
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8),
             sample(60, day: 9, hour: 9, sourceName: "iPhone", deviceModel: "iPhone17,2"),
             sample(70, day: 9, hour: 10, sourceName: "Example App", deviceModel: nil)],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50])
        XCTAssertEqual(result.diagnostics.excludedNonWatchCount, 2)
        XCTAssertEqual(result.diagnostics.fetchedCount, 3)
    }

    func testWorkoutOverlappingSamplesAreExcluded() {
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 7), sample(60, day: 9, hour: 8), sample(70, day: 9, hour: 9)],
            workouts: [workout(day: 9, startHour: 8, endHour: 9)],
            asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50, 70])
        XCTAssertEqual(result.diagnostics.excludedDuringWorkoutCount, 1)
        XCTAssertEqual(result.diagnostics.keptCount, 2)
    }

    func testDSTWindowSpansCalendarDaysNotFixedSeconds() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let asOf = newYork.date(from: DateComponents(year: 2026, month: 11, day: 2, hour: 12))!
        let window = SourcedSampleWindow.window(days: 37, asOf: asOf, calendar: newYork)
        XCTAssertEqual(newYork.dateComponents([.day], from: window.from, to: newYork.startOfDay(for: asOf)).day, 37)
        XCTAssertNotEqual(window.through.timeIntervalSince(window.from), Double(37 * 24 * 60 * 60))
        XCTAssertEqual(window.through, asOf)
    }

    func testWatchSourceDetectionAndVerbatimDisplay() {
        let watch = sample(50, day: 9, hour: 8)
        XCTAssertTrue(watch.isWatchSource)
        XCTAssertEqual(watch.displaySource, "Apple Watch · Watch7,4")
        XCTAssertFalse(watch.displaySource.contains("Series 12"))
        let watchBySource = sample(50, day: 9, hour: 8, sourceName: "My Watch App", deviceModel: nil)
        XCTAssertTrue(watchBySource.isWatchSource)
        let phone = sample(60, day: 9, hour: 9, sourceName: "iPhone", deviceModel: "iPhone17,2")
        XCTAssertFalse(phone.isWatchSource)
    }

    func testDiagnosticsMergingCombinesBothMetrics() {
        let sdnn = RawSampleDiagnostics(fetchedCount: 2, excludedNonWatchCount: 1,
                                        sources: ["Apple Watch · Watch7,4"])
        let bpm = RawSampleDiagnostics(fetchedCount: 2, droppedFutureCount: 1, truncated: true,
                                       sources: ["Apple Watch · Watch7,4", "Apple Watch · Watch8,1"])
        let merged = sdnn.merging(bpm)
        XCTAssertEqual(merged.fetchedCount, 4)
        XCTAssertEqual(merged.excludedNonWatchCount, 1)
        XCTAssertEqual(merged.droppedFutureCount, 1)
        XCTAssertTrue(merged.truncated)
        XCTAssertEqual(merged.sources.count, 2)
        XCTAssertEqual(merged.keptCount, 2)
    }
}

/// Build 28 P0-2: boundary cases for the resting filter (workout edges,
/// a sample ending exactly at `asOf`, future samples dropped before
/// duplicate dedup) and the spring-forward DST window, plus verbatim
/// diagnostics sources for kept samples only.
final class SourcedSampleBoundaryTests: XCTestCase {
    private let utc: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }()

    private func date(_ day: Int, hour: Int, minute: Int = 0) -> Date {
        utc.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func sample(_ value: Double, day: Int, hour: Int, minute: Int = 0,
                        uuid: UUID = UUID(), sourceName: String? = "Apple Watch",
                        deviceModel: String? = "Watch7,4") -> SourcedSample {
        let start = date(day, hour, minute: minute)
        return SourcedSample(value: value, start: start,
                             end: start.addingTimeInterval(5 * 60), uuid: uuid,
                             sourceName: sourceName, sourceBundleID: "com.apple.Health",
                             deviceName: "Apple Watch", deviceManufacturer: "Apple",
                             deviceModel: deviceModel)
    }

    private func workout(day: Int, startHour: Int, endHour: Int) -> DateInterval {
        DateInterval(start: date(day, startHour), end: date(day, endHour))
    }

    func testWorkoutBoundarySamplesAreKept() {
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 7, minute: 55), sample(60, day: 9, hour: 8), sample(70, day: 9, hour: 9)],
            workouts: [workout(day: 9, startHour: 8, endHour: 9)],
            asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50, 70])
        XCTAssertEqual(result.diagnostics.excludedDuringWorkoutCount, 1)
        XCTAssertEqual(result.diagnostics.fetchedCount, 3)
        XCTAssertEqual(result.diagnostics.keptCount, 2)
    }

    func testSampleEndingExactlyAtAsOfIsKept() {
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8), sample(60, day: 10, hour: 11, minute: 55)],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50, 60])
        XCTAssertEqual(result.diagnostics.droppedFutureCount, 0)
        XCTAssertEqual(result.diagnostics.fetchedCount, 2)
        XCTAssertEqual(result.diagnostics.keptCount, 2)
    }

    func testFutureSampleDoesNotCountTowardDuplicateDedup() {
        let uuid = UUID()
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8, uuid: uuid), sample(55, day: 10, hour: 13, uuid: uuid)],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50])
        XCTAssertEqual(result.diagnostics.droppedFutureCount, 1)
        XCTAssertEqual(result.diagnostics.droppedDuplicateCount, 0)
        XCTAssertEqual(result.diagnostics.fetchedCount, 2)
        XCTAssertEqual(result.diagnostics.keptCount, 1)
    }

    func testSpringForwardWindowSpansCalendarDaysNotFixedSeconds() {
        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let asOf = newYork.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 0))!
        let window = SourcedSampleWindow.window(days: 30, asOf: asOf, calendar: newYork)
        XCTAssertEqual(newYork.dateComponents([.day], from: window.from, to: newYork.startOfDay(for: asOf)).day, 30)
        XCTAssertEqual(window.through.timeIntervalSince(window.from), Double(30 * 24 * 60 * 60 - 60 * 60))
        XCTAssertEqual(window.through, asOf)
    }

    func testDiagnosticsSourcesContainOnlyKeptWatchSamples() {
        let result = selectRestingSamples(
            [sample(50, day: 9, hour: 8),
             sample(55, day: 9, hour: 9, sourceName: "My Watch App", deviceModel: nil),
             sample(60, day: 9, hour: 10, sourceName: "iPhone", deviceModel: "iPhone17,2"),
             sample(70, day: 10, hour: 13, sourceName: "Apple Watch", deviceModel: "Watch8,1")],
            workouts: [], asOf: date(10, 12), truncated: false)
        XCTAssertEqual(result.samples.map(\.value), [50, 55])
        XCTAssertEqual(result.diagnostics.excludedNonWatchCount, 1)
        XCTAssertEqual(result.diagnostics.droppedFutureCount, 1)
        XCTAssertEqual(Set(result.diagnostics.sources), Set(["Apple Watch · Watch7,4", "My Watch App"]))
        XCTAssertEqual(result.diagnostics.sources.count, 2)
    }
}
