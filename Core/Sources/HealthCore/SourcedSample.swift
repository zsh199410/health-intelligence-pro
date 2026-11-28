import Foundation

/// A HealthKit quantity sample with its provenance kept intact.
///
/// `TrendPoint` deliberately keeps only a value and a timestamp, so it
/// cannot support any claim about where a sample came from or in which
/// context it was recorded. `SourcedSample` is the layer that can: it
/// keeps the sample's start/end, UUID, source revision (source name and
/// bundle ID) and device, so the resting-context filter and the UI can
/// show the source and device model verbatim instead of inferring a
/// device series. No series name is ever derived here.
public struct SourcedSample: Equatable, Sendable {
    public let value: Double
    public let start: Date
    public let end: Date
    public let uuid: UUID
    public let sourceName: String?
    public let sourceBundleID: String?
    public let deviceName: String?
    public let deviceManufacturer: String?
    public let deviceModel: String?

    public init(value: Double, start: Date, end: Date, uuid: UUID,
                sourceName: String? = nil, sourceBundleID: String? = nil,
                deviceName: String? = nil, deviceManufacturer: String? = nil,
                deviceModel: String? = nil) {
        self.value = value
        self.start = start
        self.end = end
        self.uuid = uuid
        self.sourceName = sourceName
        self.sourceBundleID = sourceBundleID
        self.deviceName = deviceName
        self.deviceManufacturer = deviceManufacturer
        self.deviceModel = deviceModel
    }

    /// True when the sample plausibly came from an Apple Watch: the
    /// device model starts with "Watch" (for example "Watch7,4"), or
    /// the source name contains "Watch". Anything else is not treated
    /// as a Watch sample and never enters the resting model.
    public var isWatchSource: Bool {
        if let deviceModel, deviceModel.hasPrefix("Watch") { return true }
        if let sourceName, sourceName.lowercased().contains("watch") { return true }
        return false
    }

    /// The plain trend point this sample contributes once its context
    /// has been verified. Only the end date is kept, as before.
    public var trendPoint: TrendPoint {
        TrendPoint(recordedAt: end, value: value)
    }

    /// Source and device model exactly as HealthKit reported them, for
    /// example "Apple Watch · Watch7,4". The model is never mapped to
    /// a Series name: a model outside the verified list is shown as-is.
    public var displaySource: String {
        let source = sourceName ?? "未知来源"
        guard let deviceModel, !deviceModel.isEmpty else { return source }
        return "\(source) · \(deviceModel)"
    }
}

/// Counts from one raw-sample pass, for the "样本来源" row and for
/// deciding whether the resting model had trustworthy input at all.
public struct RawSampleDiagnostics: Equatable, Sendable {
    public let fetchedCount: Int
    public let excludedNonWatchCount: Int
    public let excludedDuringWorkoutCount: Int
    public let droppedDuplicateCount: Int
    public let droppedFutureCount: Int
    public let truncated: Bool
    /// Distinct display sources of the samples that survived, sorted.
    public let sources: [String]

    public init(fetchedCount: Int = 0, excludedNonWatchCount: Int = 0,
                excludedDuringWorkoutCount: Int = 0, droppedDuplicateCount: Int = 0,
                droppedFutureCount: Int = 0, truncated: Bool = false,
                sources: [String] = []) {
        self.fetchedCount = fetchedCount
        self.excludedNonWatchCount = excludedNonWatchCount
        self.excludedDuringWorkoutCount = excludedDuringWorkoutCount
        self.droppedDuplicateCount = droppedDuplicateCount
        self.droppedFutureCount = droppedFutureCount
        self.truncated = truncated
        self.sources = sources
    }

    public static var empty: RawSampleDiagnostics { RawSampleDiagnostics() }

    /// Samples that survived every check and entered the resting model.
    public var keptCount: Int {
        max(0, fetchedCount - excludedNonWatchCount - excludedDuringWorkoutCount
            - droppedDuplicateCount - droppedFutureCount)
    }

    /// Combines the SDNN and resting-heart-rate passes into one row.
    public func merging(_ other: RawSampleDiagnostics) -> RawSampleDiagnostics {
        RawSampleDiagnostics(
            fetchedCount: fetchedCount + other.fetchedCount,
            excludedNonWatchCount: excludedNonWatchCount + other.excludedNonWatchCount,
            excludedDuringWorkoutCount: excludedDuringWorkoutCount + other.excludedDuringWorkoutCount,
            droppedDuplicateCount: droppedDuplicateCount + other.droppedDuplicateCount,
            droppedFutureCount: droppedFutureCount + other.droppedFutureCount,
            truncated: truncated || other.truncated,
            sources: Array(Set(sources + other.sources)).sorted())
    }
}

/// The outcome of the resting-context filter for one metric.
public struct RestingSampleSelection: Equatable, Sendable {
    public let samples: [SourcedSample]
    public let diagnostics: RawSampleDiagnostics
}

/// Keeps only samples that can support a resting claim, oldest first:
/// the sample must not end after `asOf`; one UUID may contribute at
/// most one sample (identical duplicates collapse to one, conflicting
/// values drop the whole UUID); the sample must come from a Watch and
/// must not overlap any workout interval. Every exclusion is counted
/// in the returned diagnostics instead of being silently dropped.
public func selectRestingSamples(
    _ samples: [SourcedSample],
    workouts: [DateInterval],
    asOf: Date,
    truncated: Bool
) -> RestingSampleSelection {
    var droppedFutureCount = 0
    var droppedDuplicateCount = 0
    var excludedNonWatchCount = 0
    var excludedDuringWorkoutCount = 0

    let ordered = samples.sorted {
        if $0.start != $1.start { return $0.start < $1.start }
        if $0.end != $1.end { return $0.end < $1.end }
        return $0.uuid.uuidString < $1.uuid.uuidString
    }
    var groups: [UUID: [SourcedSample]] = [:]
    for sample in ordered {
        if sample.end > asOf {
            droppedFutureCount += 1
            continue
        }
        groups[sample.uuid, default: []].append(sample)
    }
    var deduped: [SourcedSample] = []
    for group in groups.values {
        if group.allSatisfy({ $0.value == group[0].value }) {
            deduped.append(group[0])
            droppedDuplicateCount += group.count - 1
        } else {
            droppedDuplicateCount += group.count
        }
    }
    deduped.sort { $0.start < $1.start }
    var kept: [SourcedSample] = []
    for sample in deduped {
        guard sample.isWatchSource else {
            excludedNonWatchCount += 1
            continue
        }
        let overlapsWorkout = workouts.contains {
            sample.start < $0.end && sample.end > $0.start
        }
        guard !overlapsWorkout else {
            excludedDuringWorkoutCount += 1
            continue
        }
        kept.append(sample)
    }
    let diagnostics = RawSampleDiagnostics(
        fetchedCount: samples.count,
        excludedNonWatchCount: excludedNonWatchCount,
        excludedDuringWorkoutCount: excludedDuringWorkoutCount,
        droppedDuplicateCount: droppedDuplicateCount,
        droppedFutureCount: droppedFutureCount,
        truncated: truncated,
        sources: Array(Set(kept.map(\.displaySource))).sorted())
    return RestingSampleSelection(samples: kept, diagnostics: diagnostics)
}

/// Calendar-day history windows for raw samples.
public enum SourcedSampleWindow {
    /// Window ending at `asOf`: `from` is the start of the day `days`
    /// calendar days before `asOf`, `through` is `asOf` itself.
    /// Calendar arithmetic, so a DST transition inside the window does
    /// not shorten or lengthen it by an hour.
    public static func window(days: Int, asOf: Date, calendar: Calendar = .current) -> (from: Date, through: Date) {
        let dayStart = calendar.startOfDay(for: asOf)
        let from = calendar.date(byAdding: .day, value: -days, to: dayStart) ?? dayStart
        return (from, asOf)
    }
}
