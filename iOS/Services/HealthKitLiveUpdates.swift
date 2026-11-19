import Foundation
import HealthKit

/// Watches changes to the small set of metrics shown as current on the
/// dashboard. HealthKit decides when an observer runs in the background; an
/// observer notification is never a promise of continuous sensor sampling.
@MainActor
final class HealthKitLiveUpdates {
    private struct WatchedMetric {
        let metric: HealthMetric
        var id: String { metric.id }
        var type: HKQuantityType { metric.quantityType }
        var backgroundFrequency: HKUpdateFrequency {
            // HealthKit caps step-count delivery at hourly. Use the same
            // conservative rate for the activity-energy daily total.
            switch id {
            case "stepCount", "activeEnergy": return .hourly
            default: return .immediate
            }
        }
    }

    private static let metricIDs = [
        "heartRate", "hrv", "restingHeartRate", "stepCount", "activeEnergy",
        "respiratoryRate", "oxygenSaturation"
    ]
    private let store = HKHealthStore()
    private let onChange: @MainActor (Set<String>) async -> Void
    private let onBackgroundDeliveryResult: @MainActor (String, String?) -> Void
    private var observers: [String: HKObserverQuery] = [:]
    private var queuedIDs = Set<String>()
    private var runningIDs = Set<String>()
    private var completions: [String: [() -> Void]] = [:]

    init(onChange: @escaping @MainActor (Set<String>) async -> Void,
         onBackgroundDeliveryResult: @escaping @MainActor (String, String?) -> Void) {
        self.onChange = onChange
        self.onBackgroundDeliveryResult = onBackgroundDeliveryResult
    }

    func start() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        for watched in Self.watchedMetrics where observers[watched.id] == nil {
            let observer = HKObserverQuery(sampleType: watched.type, predicate: nil) { [weak self] _, completion, error in
                Task { @MainActor in
                    guard let self, error == nil else { completion(); return }
                    self.enqueue(watched, completion: completion)
                }
            }
            observers[watched.id] = observer
            store.execute(observer)
            // Requested frequency is not a sampling rate or a guarantee
            // that the app will run for every new reading.
            store.enableBackgroundDelivery(for: watched.type, frequency: watched.backgroundFrequency) {
                [weak self] success, error in
                Task { @MainActor in
                    self?.onBackgroundDeliveryResult(
                        watched.id,
                        success ? nil : (error?.localizedDescription ?? "系统未启用后台更新")
                    )
                }
            }
        }
    }

    /// Reconcile missed samples after suspension or a foreground transition.
    func catchUp() {
        guard HKHealthStore.isHealthDataAvailable() else { return }
        start()
        for watched in Self.watchedMetrics { enqueue(watched, completion: nil) }
    }

    private static var watchedMetrics: [WatchedMetric] {
        metricIDs.compactMap { id in
            HealthCatalog.byID[id].map { WatchedMetric(metric: $0) }
        }
    }

    private func enqueue(_ watched: WatchedMetric, completion: (() -> Void)?) {
        if let completion { completions[watched.id, default: []].append(completion) }
        queuedIDs.insert(watched.id)
        guard runningIDs.insert(watched.id).inserted else { return }
        Task { @MainActor in await process(watched) }
    }

    private func process(_ watched: WatchedMetric) async {
        while queuedIDs.remove(watched.id) != nil {
            let callbacks = completions.removeValue(forKey: watched.id) ?? []
            defer { callbacks.forEach { $0() } }
            // The anchor covers additions and deletions. Re-read the current
            // metric after either kind of change: a deleted latest sample may
            // reveal an older one, or may leave the metric empty.
            try? await drainAnchor(for: watched)
            await onChange([watched.id])
        }
        runningIDs.remove(watched.id)
    }

    private func drainAnchor(for watched: WatchedMetric) async throws {
        var anchor = savedAnchor(for: watched.id)
        // Bound the first reconciliation. Historic samples remain available
        // through normal metric queries; this feed only detects recent edits.
        let start = Date().addingTimeInterval(-7 * 24 * 60 * 60)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: nil)
        while true {
            let page = try await anchoredPage(type: watched.type, predicate: predicate, anchor: anchor)
            guard let next = page.anchor else { return }
            let advanced = anchor?.isEqual(next) != true
            save(next, for: watched.id)
            anchor = next
            if page.count < 500 || !advanced { return }
        }
    }

    private func anchoredPage(type: HKSampleType, predicate: NSPredicate?, anchor: HKQueryAnchor?) async throws
        -> (anchor: HKQueryAnchor?, count: Int) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(type: type, predicate: predicate, anchor: anchor,
                                              limit: 500) { _, added, deleted, newAnchor, error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume(returning: (newAnchor, (added?.count ?? 0) + (deleted?.count ?? 0))) }
            }
            store.execute(query)
        }
    }

    private func savedAnchor(for id: String) -> HKQueryAnchor? {
        guard let data = UserDefaults.standard.data(forKey: anchorKey(id)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }

    private func save(_ anchor: HKQueryAnchor, for id: String) {
        guard let data = try? NSKeyedArchiver.archivedData(withRootObject: anchor,
                                                           requiringSecureCoding: true) else { return }
        UserDefaults.standard.set(data, forKey: anchorKey(id))
    }

    private func anchorKey(_ id: String) -> String { "health.live.anchor.\(id)" }
}
