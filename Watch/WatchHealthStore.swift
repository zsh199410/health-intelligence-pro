import Foundation
import Combine
import HealthKit
import HealthCore

@MainActor
final class WatchHealthStore: ObservableObject {
    @Published private(set) var readings: [String: MetricReading] = [:]
    @Published private(set) var sleep: SleepSummary?
    /// Latest sleep session window, for the sleep section header.
    @Published private(set) var sleepWindow: ClosedRange<Date>?
    @Published private(set) var isLoading = false
    @Published var errorMessage: String?

    private let store = HKHealthStore()
    private let definitions: [(String, String, HKQuantityTypeIdentifier, HKUnit, Double)] = [
        ("heartRate", "心率", .heartRate, .count().unitDivided(by: .minute()), 1),
        ("restingHeartRate", "静息心率", .restingHeartRate, .count().unitDivided(by: .minute()), 1),
        ("hrv", "HRV", .heartRateVariabilitySDNN, .secondUnit(with: .milli), 1),
        ("oxygenSaturation", "血氧", .oxygenSaturation, .percent(), 100),
        ("respiratoryRate", "呼吸频率", .respiratoryRate, .count().unitDivided(by: .minute()), 1)
    ]

    func authorize() async {
        guard !isLoading else { return }
        guard HKHealthStore.isHealthDataAvailable() else {
            errorMessage = "当前手表不支持健康记录访问"; return
        }
        isLoading = true
        defer { isLoading = false }
        var read: Set<HKObjectType> = Set(definitions.compactMap {
            HKObjectType.quantityType(forIdentifier: $0.2) as HKObjectType?
        })
        if let sleepType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            read.insert(sleepType)
        }
        do {
            try await store.requestAuthorization(toShare: [], read: read)
            await loadReadings()
        } catch { errorMessage = "授权请求失败：\(error.localizedDescription)" }
    }

    func refresh() async {
        guard HKHealthStore.isHealthDataAvailable(), !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        await loadReadings()
    }

    private func loadReadings() async {
        var failed: [String] = []
        var result: [String: MetricReading] = [:]
        for (id, name, identifier, unit, multiplier) in definitions {
            guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { continue }
            let sample: HKQuantitySample
            do {
                guard let latestSample = try await latest(type) else { continue }
                sample = latestSample
            } catch {
                failed.append(name)
                continue
            }
            let value = sample.quantity.doubleValue(for: unit) * multiplier
            guard value.isFinite else { continue }
            result[id] = MetricReading(id: id, value: value, unit: "", recordedAt: sample.endDate,
                                       source: sample.sourceRevision.source.name)
        }
        readings = result
        do {
            let intervals = try await latestSleepIntervals()
            let session = SleepSession.latest(from: intervals)
            sleep = session.map { SleepCalculator.summarize($0.intervals) }
            sleepWindow = session?.window
        } catch {
            sleep = nil
            sleepWindow = nil
            failed.append("睡眠")
        }
        if failed.isEmpty {
            errorMessage = nil
            WatchStatusBridge.shared.sendRefreshDate(Date())
        } else {
            errorMessage = "读取失败：" + failed.joined(separator: "、") + "。请稍后刷新。"
        }
    }

    private func latestSleepIntervals() async throws -> [SleepInterval] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let from = Calendar.current.date(byAdding: .hour, value: -36, to: Date())!
        let samples: [HKCategorySample] = try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type,
                                      predicate: HKQuery.predicateForSamples(withStart: from, end: Date()),
                                      limit: 300,
                                      sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) { _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.compactMap { $0 as? HKCategorySample } ?? []) }
            }
            store.execute(query)
        }
        return samples.compactMap { item in
            guard let value = HKCategoryValueSleepAnalysis(rawValue: item.value) else { return nil }
            let stage: SleepStage
            switch value {
            case .awake: stage = .awake
            case .asleepREM: stage = .rem
            case .asleepCore: stage = .core
            case .asleepDeep: stage = .deep
            case .asleepUnspecified: stage = .unspecified
            default: return nil
            }
            return SleepInterval(start: item.startDate, end: item.endDate, stage: stage)
        }
    }

    private func latest(_ type: HKQuantityType) async throws -> HKQuantitySample? {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: nil, limit: 1,
                                     sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]) {
                _, samples, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: samples?.first as? HKQuantitySample) }
            }
            store.execute(query)
        }
    }
}
