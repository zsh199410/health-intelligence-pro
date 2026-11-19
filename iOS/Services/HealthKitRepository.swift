import Foundation
import HealthKit
import HealthCore

struct WorkoutRecord: Identifiable {
    let id: UUID
    let start: Date
    let end: Date
    let activity: HKWorkoutActivityType
    let source: String
    var name: String {
        switch activity {
        case .walking: return "步行"
        case .running: return "跑步"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "力量训练"
        default: return "训练记录"
        }
    }
}

/// HealthKit reads are independent of WatchConnectivity.
/// Important: read access denial cannot be reliably distinguished from empty data.
final class HealthKitRepository {
    private let store = HKHealthStore()
    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        var read: Set<HKObjectType> = Set(HealthCatalog.all.map { $0.quantityType as HKObjectType })
        read.insert(HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!)
        read.insert(HKObjectType.electrocardiogramType())
        read.insert(HKObjectType.workoutType())
        for identifier in [HKCategoryTypeIdentifier.highHeartRateEvent,
                           .lowHeartRateEvent, .irregularHeartRhythmEvent] {
            if let type = HKObjectType.categoryType(forIdentifier: identifier) { read.insert(type) }
        }
        // Launch requests read-only access. Write permissions are requested
        // lazily, only when the user actually saves a measurement, so a
        // problem with a write type cannot crash the app on launch.
        // (2026-11-17: requesting the write set on launch crashed on a real
        // device with _throwIfAuthorizationDisallowedForSharing, before any
        // data was read.)
        try await store.requestAuthorization(toShare: [], read: read)
        // Successful completion means the sheet completed, not that reads were granted.
    }

    /// Requests write authorization for user-entered measurements only.
    /// Called lazily from the save functions, never on launch.
    func requestWriteAccess() async throws {
        guard isAvailable else { throw HealthError.unavailable }
        // Write permissions are limited to explicitly user-entered measurements.
        let write: Set<HKSampleType> = [
            HKObjectType.quantityType(forIdentifier: .bodyMass)!,
            HKObjectType.quantityType(forIdentifier: .bloodGlucose)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
            HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
            HKObjectType.correlationType(forIdentifier: .bloodPressure)!
        ]
        try await store.requestAuthorization(toShare: write, read: [])
    }

    func reading(_ metric: HealthMetric) async throws -> MetricReading? {
        let value: Double?
        let date: Date
        let source: String
        switch metric.aggregation {
        case .latest:
            guard let sample = try await latestQuantity(metric.quantityType) else { return nil }
            value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
            date = sample.endDate
            source = sample.sourceRevision.source.name
        case .sumToday:
            let (total, latestSampleDate) = try await todaySum(metric.quantityType, unit: metric.unit)
            guard let latestSampleDate else { return nil }
            value = total.map { $0 * metric.multiplier }
            date = latestSampleDate
            source = "HealthKit 日累计"
        }
        guard let value, value.isFinite else { return nil }
        return MetricReading(id: metric.id, value: value, unit: metric.unitText,
                             recordedAt: date, source: source)
    }

    /// Latest sample of a `.latest` metric overlapping `window`, or nil when
    /// no sample exists inside it. Never falls back to a sample outside the
    /// window: a daytime reading must not stand in for a night reading.
    /// Used for the sleep page, where `window` is the latest sleep session.
    func reading(_ metric: HealthMetric, in window: ClosedRange<Date>) async throws -> MetricReading? {
        guard metric.aggregation == .latest else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: window.lowerBound, end: window.upperBound)
        let samples = try await sampleQuery(type: metric.quantityType, predicate: predicate, limit: 1)
        guard let sample = samples.first as? HKQuantitySample else { return nil }
        let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
        guard value.isFinite else { return nil }
        return MetricReading(id: metric.id, value: value, unit: metric.unitText,
                             recordedAt: sample.endDate, source: sample.sourceRevision.source.name)
    }

    /// One aggregated point per calendar day. This avoids silently truncating
    /// high-frequency Series 12 readings after an arbitrary 120 raw samples.
    func trend(_ metric: HealthMetric, days: Int = 30) async throws -> [TrendPoint] {
        let calendar = Calendar.current
        let anchor = calendar.startOfDay(for: Date())
        guard let start = calendar.date(byAdding: .day, value: -(max(2, days) - 1), to: anchor) else { return [] }
        let end = Date()
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let option: HKStatisticsOptions = metric.aggregation == .sumToday ? .cumulativeSum : .discreteAverage
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(quantityType: metric.quantityType,
                                                     quantitySamplePredicate: predicate,
                                                     options: option,
                                                     anchorDate: anchor,
                                                     intervalComponents: DateComponents(day: 1))
            query.initialResultsHandler = { _, collection, error in
                if let error { continuation.resume(throwing: error); return }
                guard let collection else { continuation.resume(returning: []); return }
                var result: [TrendPoint] = []
                collection.enumerateStatistics(from: start, to: end) { statistics, _ in
                    let quantity = option == .cumulativeSum ? statistics.sumQuantity() : statistics.averageQuantity()
                    guard let quantity else { return }
                    let value = quantity.doubleValue(for: metric.unit) * metric.multiplier
                    guard value.isFinite else { return }
                    result.append(TrendPoint(recordedAt: statistics.startDate, value: value))
                }
                continuation.resume(returning: result.sorted { $0.recordedAt < $1.recordedAt })
            }
            self.store.execute(query)
        }
    }

    /// Raw samples of a metric over the last `hours` hours, oldest first.
    /// Used by the stress page, which needs within-day (hourly) samples;
    /// `trend` aggregates per day and cannot serve that. Values use the
    /// metric unit and multiplier, non-finite values are dropped. Only
    /// the newest `limit` samples are read; the result is re-sorted
    /// ascending because `sampleQuery` returns newest first.
    func samples(_ metric: HealthMetric, hours: Int, limit: Int = 500) async throws -> [TrendPoint] {
        guard let start = Calendar.current.date(byAdding: .hour, value: -max(1, hours), to: Date()) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let raw = try await sampleQuery(type: metric.quantityType, predicate: predicate, limit: limit)
        var result: [TrendPoint] = []
        for case let sample as HKQuantitySample in raw {
            let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
            guard value.isFinite else { continue }
            result.append(TrendPoint(recordedAt: sample.endDate, value: value))
        }
        return result.sorted { $0.recordedAt < $1.recordedAt }
    }

    func recentWorkouts(limit: Int = 20) async throws -> [WorkoutRecord] {
        let samples = try await sampleQuery(type: HKObjectType.workoutType(), predicate: nil, limit: limit)
        return samples.compactMap { sample in
            guard let workout = sample as? HKWorkout else { return nil }
            return WorkoutRecord(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                                 activity: workout.workoutActivityType,
                                 source: workout.sourceRevision.source.name)
        }
    }

    func sleepIntervals() async throws -> [SleepInterval] {
        let since = Calendar.current.date(byAdding: .hour, value: -36, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now)
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples = try await sampleQuery(type: sleepType, predicate: predicate, limit: 250)
        return samples.compactMap { sample in
            guard let sample = sample as? HKCategorySample,
                  let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepUnspecified: stage = .unspecified
            case .awake: stage = .awake
            default: return nil // .inBed overlaps with actual stages
            }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
    }

    /// Sleep session windows over the last `days` days, for sleep
    /// regularity (bedtime / wake-time consistency). Same 2-hour gap
    /// sessionization as `SleepSession.window`, but returns every
    /// session, newest first. Empty when there is no sleep record.
    func sleepSessions(days: Int = 7) async throws -> [ClosedRange<Date>] {
        let since = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        let predicate = HKQuery.predicateForSamples(withStart: since, end: .now)
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples = try await sampleQuery(type: sleepType, predicate: predicate, limit: 1000)
        let intervals = samples.compactMap { sample -> SleepInterval? in
            guard let sample = sample as? HKCategorySample,
                  let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepUnspecified: stage = .unspecified
            case .awake: stage = .awake
            default: return nil // .inBed overlaps with actual stages
            }
            return SleepInterval(start: sample.startDate, end: sample.endDate, stage: stage)
        }
        let sorted = intervals.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        let maxGap: TimeInterval = 2 * 3600
        var sessions: [ClosedRange<Date>] = []
        var runStart = sorted[0].start
        var runEnd = sorted[0].end
        for interval in sorted.dropFirst() {
            if interval.start.timeIntervalSince(runEnd) < maxGap {
                runStart = min(runStart, interval.start)
                runEnd = max(runEnd, interval.end)
            } else {
                sessions.append(runStart...runEnd)
                runStart = interval.start
                runEnd = interval.end
            }
        }
        sessions.append(runStart...runEnd)
        return sessions.reversed()
    }

    func ecgSummaries() async throws -> [ECGSummary] {
        let samples = try await sampleQuery(type: HKObjectType.electrocardiogramType(),
                                            predicate: nil, limit: 20)
        return samples.compactMap { sample in
            guard let ecg = sample as? HKElectrocardiogram else { return nil }
            return ECGSummary(id: ecg.uuid, recordedAt: ecg.startDate,
                              classification: ecgDescription(ecg.classification),
                              averageHeartRate: ecg.averageHeartRate?.doubleValue(for: HealthCatalog.pulseUnit))
        }
    }

    /// System-generated heart notifications. Read-only and may be empty for permission reasons.
    func heartEvents() async throws -> [HeartEvent] {
        let kinds: [(HKCategoryTypeIdentifier, String)] = [
            (.highHeartRateEvent, "系统高心率通知"),
            (.lowHeartRateEvent, "系统低心率通知"),
            (.irregularHeartRhythmEvent, "系统不规则心律通知")
        ]
        var result: [HeartEvent] = []
        for (identifier, label) in kinds {
            guard let type = HKObjectType.categoryType(forIdentifier: identifier) else { continue }
            let samples = try await sampleQuery(type: type, predicate: nil, limit: 20)
            for case let sample as HKCategorySample in samples {
                result.append(HeartEvent(id: sample.uuid, type: label,
                                         date: sample.endDate, source: sample.sourceRevision.source.name))
            }
        }
        return result.sorted { $0.date > $1.date }.prefix(30).map { $0 }
    }

    /// Reads an existing ECG waveform on demand; does not trigger a new ECG measurement.
    func ecgVoltagePoints(id: UUID) async throws -> [ECGVoltagePoint] {
        let samples = try await sampleQuery(type: HKObjectType.electrocardiogramType(), predicate: nil, limit: 100)
        guard let ecg = samples.compactMap({ $0 as? HKElectrocardiogram }).first(where: { $0.uuid == id })
        else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            let lock = NSLock()
            var points: [ECGVoltagePoint] = []
            var completed = false
            let query = HKElectrocardiogramQuery(electrocardiogram: ecg) { _, measurement, done, error in
                lock.lock()
                defer { lock.unlock() }
                guard !completed else { return }
                if let error {
                    completed = true; continuation.resume(throwing: error); return
                }
                if let measurement,
                   let quantity = measurement.quantity(for: .appleWatchSimilarToLeadI) {
                    let value = quantity.doubleValue(for: .voltUnit(with: .milli))
                    if value.isFinite {
                        points.append(ECGVoltagePoint(seconds: measurement.timeSinceSampleStart,
                                                      millivolts: value))
                    }
                }
                if done {
                    completed = true
                    // Downsample for a responsive chart; full ECG export requires a dedicated audited path.
                    let strideSize = max(1, points.count / 1600)
                    continuation.resume(returning: Swift.stride(from: 0, to: points.count, by: strideSize).map { points[$0] })
                }
            }
            store.execute(query)
        }
    }

    func saveWeight(_ kg: Double) async throws {
        guard (15...350).contains(kg) else { throw HealthError.invalidValue }
        try await requestWriteAccess()
        let type = HKObjectType.quantityType(forIdentifier: .bodyMass)!
        let sample = HKQuantitySample(type: type,
                                      quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg),
                                      start: Date(), end: Date())
        try await save(sample)
    }

    func saveGlucose(_ mgdl: Double) async throws {
        guard (20...800).contains(mgdl) else { throw HealthError.invalidValue }
        try await requestWriteAccess()
        let type = HKObjectType.quantityType(forIdentifier: .bloodGlucose)!
        let now = Date()
        let sample = HKQuantitySample(type: type,
                                      quantity: HKQuantity(unit: HealthCatalog.mgdl, doubleValue: mgdl),
                                      start: now, end: now)
        try await save(sample)
    }

    func saveBloodPressure(systolic: Double, diastolic: Double) async throws {
        guard (50...300).contains(systolic), (30...200).contains(diastolic), systolic > diastolic else {
            throw HealthError.invalidValue
        }
        try await requestWriteAccess()
        let now = Date()
        let systolicSample = HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic)!,
                                              quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: systolic),
                                              start: now, end: now)
        let diastolicSample = HKQuantitySample(type: HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic)!,
                                               quantity: HKQuantity(unit: .millimeterOfMercury(), doubleValue: diastolic),
                                               start: now, end: now)
        let correlation = HKCorrelation(type: HKObjectType.correlationType(forIdentifier: .bloodPressure)!,
                                        start: now, end: now, objects: [systolicSample, diastolicSample])
        try await save(correlation)
    }

    private func latestQuantity(_ type: HKQuantityType) async throws -> HKQuantitySample? {
        let samples = try await sampleQuery(type: type, predicate: nil, limit: 1)
        return samples.first as? HKQuantitySample
    }

    private func todaySum(_ type: HKQuantityType, unit: HKUnit) async throws -> (Double?, Date?) {
        let start = Calendar.current.startOfDay(for: .now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date())
        let total: Double? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
            }
            store.execute(query)
        }
        guard total != nil else { return (nil, nil) }
        let samples = try await sampleQuery(type: type, predicate: predicate, limit: 1)
        let latest = samples.first as? HKQuantitySample
        // `Date()` would only say when this query ran. Keep the latest
        // contributing sample's time so the UI can identify an old total.
        return (total, latest?.endDate)
    }

    private func sampleQuery(type: HKSampleType, predicate: NSPredicate?, limit: Int) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let sort = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit,
                                      sortDescriptors: sort) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    private func save(_ sample: HKObject) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            store.save(sample) { success, error in
                if let error { continuation.resume(throwing: error) }
                else if success { continuation.resume(returning: ()) }
                else { continuation.resume(throwing: HealthError.failedSave) }
            }
        }
    }

    private func ecgDescription(_ status: HKElectrocardiogram.Classification) -> String {
        switch status {
        case .sinusRhythm: return "窦性心律（系统分类）"
        case .atrialFibrillation: return "房颤提示（系统分类）"
        case .inconclusiveOther: return "无法确定具体原因（系统分类）"
        case .inconclusiveHighHeartRate: return "心率偏高，无法分类（系统分类）"
        case .inconclusiveLowHeartRate: return "心率偏低，无法分类（系统分类）"
        case .inconclusivePoorReading: return "记录质量不足（系统分类）"
        case .unrecognized: return "当前系统无法识别该 ECG 分类"
        case .notSet: return "系统尚未提供 ECG 分类"
        default: return "系统分类码：\(status.rawValue)"
        }
    }
}

enum HealthError: LocalizedError {
    case unavailable, invalidValue, failedSave
    var errorDescription: String? {
        switch self {
        case .unavailable: return "当前设备不提供 HealthKit 服务"
        case .invalidValue: return "请输入合理的测量值，且收缩压应大于舒张压"
        case .failedSave: return "保存失败，请检查健康写入权限"
        }
    }
}
