import Foundation
import Combine
import HealthCore

/// Loads the last 24 hours of raw samples behind the stress page and
/// buckets them into natural hours. Read-only; never fabricates values.
/// A failed metric is recorded in `failedIDs` and never reported as
/// success. Step count and activity energy are summed per hour; heart
/// rate, HRV and respiratory rate take the hourly median.
@MainActor
final class StressDataLoader: ObservableObject {
    static let metricIDs = ["heartRate", "hrv", "respiratoryRate", "stepCount", "activeEnergy"]

    @Published private(set) var samples: [String: [TrendPoint]] = [:]
    @Published private(set) var isLoading = false
    @Published private(set) var failedIDs: [String] = []
    @Published private(set) var loadedAt: Date?

    private let repository: HealthKitRepository

    init(repository: HealthKitRepository) {
        self.repository = repository
    }

    func load() async {
        guard isLoading == false else { return }
        isLoading = true
        defer { isLoading = false }
        var loaded: [String: [TrendPoint]] = [:]
        var failures: [String] = []
        for id in Self.metricIDs {
            guard let metric = HealthCatalog.byID[id] else { continue }
            do {
                loaded[id] = try await repository.samples(metric, hours: 24)
            } catch {
                failures.append(id)
            }
        }
        samples = loaded
        failedIDs = failures
        loadedAt = .now
    }

    /// Natural-hour buckets with at least one sample, oldest first.
    /// Resting heart rate is the latest daily value, supplied by the
    /// caller from `HealthViewModel.readings` so it is not read twice.
    /// Hours with no sample at all are omitted here; the view renders
    /// them as gaps from the 24-hour window, never as zeros.
    func hourlyInputs(restingHeartRate: Double?) -> [StressHourInput] {
        let calendar = Calendar.current
        var hours: [Date: [String: [Double]]] = [:]
        for (id, points) in samples {
            for point in points {
                let hourStart = calendar.date(
                    from: calendar.dateComponents([.year, .month, .day, .hour], from: point.recordedAt)
                ) ?? point.recordedAt
                var bucket = hours[hourStart] ?? [:]
                bucket[id, default: []].append(point.value)
                hours[hourStart] = bucket
            }
        }
        return hours.keys.sorted().map { hourStart in
            let bucket = hours[hourStart] ?? [:]
            return StressHourInput(
                hourStart: hourStart,
                hrvMedian: median(bucket["hrv"] ?? []),
                restingHeartRate: restingHeartRate,
                heartRateMedian: median(bucket["heartRate"] ?? []),
                respiratoryRateMedian: median(bucket["respiratoryRate"] ?? []),
                steps: bucket["stepCount"].map { $0.reduce(0, +) },
                activeEnergyKcal: bucket["activeEnergy"].map { $0.reduce(0, +) }
            )
        }
    }

    /// Whether any physiological signal (heart rate, HRV, respiratory
    /// rate) has at least one sample. Steps / energy alone do not count.
    var hasPhysiologicalSamples: Bool {
        for id in ["heartRate", "hrv", "respiratoryRate"] {
            if let points = samples[id], points.isEmpty == false {
                return true
            }
        }
        return false
    }

    private func median(_ values: [Double]) -> Double? {
        let numbers = values.filter { $0.isFinite }.sorted()
        guard numbers.isEmpty == false else { return nil }
        let middle = numbers.count / 2
        if numbers.count.isMultiple(of: 2) {
            return (numbers[middle - 1] + numbers[middle]) / 2
        }
        return numbers[middle]
    }
}
