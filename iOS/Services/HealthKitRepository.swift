import Foundation
import HealthKit
import HealthCore

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
            guard let (total, lastSampleEnd) = try await todaySum(metric.quantityType, unit: metric.unit) else { return nil }
            value = total * metric.multiplier
            date = lastSampleEnd
            source = "HealthKit 日累计 · 最近样本"
        }
        guard let value, value.isFinite else { return nil }
        return MetricReading(id: metric.id, value: value, unit: metric.unitText,
                             recordedAt: date, source: source)
    }

    /// Latest sample of a `.latest` metric ending in `window`, or nil when
    /// no sample exists inside it. Never falls back to a sample outside the
    /// window: a daytime reading must not stand in for a night reading.
    /// Used for the sleep page, where `window` is the latest sleep session.
    func reading(_ metric: HealthMetric, in window: ClosedRange<Date>) async throws -> MetricReading? {
        guard metric.aggregation == .latest else { return nil }
        // The displayed record time is the sample end. Restrict that time
        // before sorting and limiting so a later overlapping sample cannot
        // displace the last record from the sleep session.
        let predicate = HKQuery.predicateForSamples(withStart: window.lowerBound, end: window.upperBound,
                                      options: .strictEndDate)
        let samples = try await sampleQuery(type: metric.quantityType, predicate: predicate, limit: 1)
        guard let sample = samples.first as? HKQuantitySample else { return nil }
        let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
        guard value.isFinite else { return nil }
        return MetricReading(id: metric.id, value: value, unit: metric.unitText,
                             recordedAt: sample.endDate, source: sample.sourceRevision.source.name)
    }

    /// One aggregated point per calendar day. This avoids silently truncating
    /// high-frequency Series 12 readings after an arbitrary 120 raw samples.
    func trend(_ metric: HealthMetric, days: Int = 30, endingAt end: Date = Date(),
               calendar: Calendar = .current) async throws -> [TrendPoint] {
        let anchor = calendar.startOfDay(for: end)
        guard let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: anchor) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate, .strictEndDate])
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

    /// Raw sourced samples of a metric in `from...through`, oldest first.
    /// One shared implementation backs both `sourcedSamples` and `samples`:
    /// the caller fixes the window, this function never reads the clock.
    /// Values use the metric unit and multiplier, non-finite values are
    /// dropped. Only the newest `limit` samples are kept; `truncated`
    /// reports whether more samples exist in the window than `limit`.
    /// The result is re-sorted ascending because `sampleQuery` returns
    /// newest first.
    func sourcedSamples(_ metric: HealthMetric, from: Date, through: Date,
                        limit: Int = 500) async throws -> (samples: [SourcedSample], truncated: Bool) {
        let capped = limit == HKObjectQueryNoLimit ? HKObjectQueryNoLimit : max(1, limit)
        let fetchLimit = capped == HKObjectQueryNoLimit ? capped : capped + 1
        let predicate = HKQuery.predicateForSamples(withStart: from, end: through)
        let raw = try await sampleQuery(type: metric.quantityType, predicate: predicate, limit: fetchLimit)
        let truncated = capped != HKObjectQueryNoLimit && raw.count > capped
        let kept = capped == HKObjectQueryNoLimit ? raw : Array(raw.prefix(capped))
        var result: [SourcedSample] = []
        for case let sample as HKQuantitySample in kept {
            let value = sample.quantity.doubleValue(for: metric.unit) * metric.multiplier
            guard value.isFinite else { continue }
            let revision = sample.sourceRevision
            result.append(SourcedSample(value: value, start: sample.startDate, end: sample.endDate,
                                        uuid: sample.uuid, sourceName: revision.source.name,
                                        sourceBundleID: revision.source.bundleIdentifier,
                                        deviceName: sample.device?.name,
                                        deviceManufacturer: sample.device?.manufacturer,
                                        deviceModel: sample.device?.model))
        }
        return (result.sorted { $0.end < $1.end }, truncated)
    }

    /// Raw samples of a metric in `from...through`, oldest first, as
    /// TrendPoints. Used by the stress page, which needs within-day
    /// (hourly) samples; `trend` aggregates per day and cannot serve that.
    /// Shares the `sourcedSamples` implementation; the caller fixes the
    /// window, this function never reads the clock.
    func samples(_ metric: HealthMetric, from: Date, through: Date, limit: Int = 500) async throws -> [TrendPoint] {
        let (sourced, _) = try await sourcedSamples(metric, from: from, through: through, limit: limit)
        return sourced.map(\.trendPoint)
    }

    /// Workouts in the window as RatedWorkout with exertion nil: session RPE
    /// is a real user rating (0-10) and is applied by the caller from the
    /// locally stored inputs, never guessed from heart rate or energy.
    /// Active minutes come from start/end minus pause spans in the workout
    /// events, so a paused session does not count paused time as training.
    /// Without events the full elapsed time counts.
    func workouts(from startDate: Date, through now: Date) async throws -> [RatedWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now)
        let raw = try await sampleQuery(type: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit)
        return raw.compactMap { sample in
            guard let workout = sample as? HKWorkout, workout.endDate > workout.startDate else { return nil }
            var paused: TimeInterval = 0
            var pauseStart: Date?
            for event in workout.workoutEvents ?? [] {
                if event.type == .pause {
                    if pauseStart == nil { pauseStart = event.date }
                } else if event.type == .resume {
                    if let start = pauseStart {
                        paused += event.date.timeIntervalSince(start)
                        pauseStart = nil
                    }
                }
            }
            if let start = pauseStart { paused += workout.endDate.timeIntervalSince(start) }
            let active = max(0, workout.endDate.timeIntervalSince(workout.startDate) - paused) / 60
            guard active > 0, active.isFinite else { return nil }
            return RatedWorkout(id: workout.uuid, start: workout.startDate, end: workout.endDate,
                                activeMinutes: active, exertion: nil)
        }.sorted { $0.start < $1.start }
    }


    /// Workout activity types by workout UUID, for display names. Runs the
    /// same query as workouts(); callers that need both should call both.
    func workoutActivityTypes(from startDate: Date, through now: Date) async throws -> [UUID: HKWorkoutActivityType] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: now)
        let raw = try await sampleQuery(type: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit)
        var result: [UUID: HKWorkoutActivityType] = [:]
        for case let workout as HKWorkout in raw {
            result[workout.uuid] = workout.workoutActivityType
        }
        return result
    }

    func sleepIntervals(from startDate: Date? = nil, through now: Date = Date()) async throws -> [SleepInterval] {
        let since = startDate ?? now.addingTimeInterval(-36 * 3600)
        let predicate = HKQuery.predicateForSamples(withStart: since, end: now)
        let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!
        let samples = try await sampleQuery(type: sleepType, predicate: predicate, limit: HKObjectQueryNoLimit)
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
            let start = max(since, sample.startDate)
            let end = min(now, sample.endDate)
            guard start < end else { return nil }
            return SleepInterval(start: start, end: end, stage: stage)
        }
    }

    func ecgSummaries() async throws -> [ECGSummary] {
        let now = Date()
        let cal = Calendar.current
        guard let start = cal.date(byAdding: .day, value: -89, to: cal.startOfDay(for: now)) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: [.strictStartDate, .strictEndDate])
        let samples = try await sampleQuery(type: HKObjectType.electrocardiogramType(), predicate: predicate, limit: HKObjectQueryNoLimit)
        return samples.compactMap { sample in
            guard let ecg = sample as? HKElectrocardiogram else { return nil }
            return ECGSummary(id: ecg.uuid, recordedAt: ecg.startDate,
                              classification: ecgDescription(ecg.classification),
                              averageHeartRate: ecg.averageHeartRate?.doubleValue(for: HealthCatalog.pulseUnit),
                              source: ecg.sourceRevision.source.name,
                              duration: ecg.endDate.timeIntervalSince(ecg.startDate))
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
    func ecgWaveform(id: UUID) async throws -> ECGWaveform? {
        let samples = try await sampleQuery(type: HKObjectType.electrocardiogramType(),
                                            predicate: HKQuery.predicateForObject(with: id), limit: 1)
        guard let ecg = samples.first as? HKElectrocardiogram else { return nil }
        let frequency = ecg.samplingFrequency?.doubleValue(for: .hertz())
        let samplesInLead: [ECGVoltagePoint] = try await withCheckedThrowingContinuation { continuation in
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
                    points.append(ECGVoltagePoint(seconds: measurement.timeSinceSampleStart, millivolts: value))
                }
                if done {
                    completed = true
                    continuation.resume(returning: points)
                }
            }
            store.execute(query)
        }
        guard !samplesInLead.isEmpty else { return nil }
        return try ECGWaveform(samples: samplesInLead, samplingFrequency: frequency)
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
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: .now, options: .strictEndDate)
        let samples = try await sampleQuery(type: type, predicate: predicate, limit: 1)
        return samples.first as? HKQuantitySample
    }

    private func todaySum(_ type: HKQuantityType, unit: HKUnit) async throws -> (Double, Date)? {
        let now = Date()
        let start = Calendar.current.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictEndDate)
        let samples = try await sampleQuery(type: type, predicate: predicate, limit: 1)
        guard let mostRecent = samples.first else { return nil }
        let total: Double? = try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate,
                                          options: .cumulativeSum) { _, statistics, error in
                if let error = error as? HKError, error.code == .errorNoData {
                    continuation.resume(returning: nil)
                } else if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: statistics?.sumQuantity()?.doubleValue(for: unit))
                }
            }
            store.execute(query)
        }
        return total.map { ($0, mostRecent.endDate) }
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
