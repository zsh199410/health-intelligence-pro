import Foundation
import Combine
import HealthCore

@MainActor
final class HealthViewModel: ObservableObject {
    @Published private(set) var readings: [String: MetricReading] = [:]
    @Published private(set) var trends: [String: [TrendPoint]] = [:]
    @Published private(set) var sleep: SleepSummary?
    /// Latest sleep session window, derived from the same intervals that
    /// produce `sleep`. Nil when there is no sleep record.
    @Published private(set) var sleepWindow: ClosedRange<Date>?
    /// Night vitals: latest sample of each night metric whose record falls
    /// inside `sleepWindow`. Never falls back to a daytime reading.
    @Published private(set) var nightReadings: [String: MetricReading] = [:]
    /// Metric IDs whose HealthKit query threw (a read error, not empty data).
    /// Empty data and a denied read look identical by HealthKit design and
    /// are NOT recorded here.
    @Published private(set) var failedMetricIDs: [String] = []
    @Published private(set) var ecgs: [ECGSummary] = []
    @Published private(set) var heartEvents: [HeartEvent] = []
    @Published private(set) var ecgVoltages: [UUID: [ECGVoltagePoint]] = [:]
    @Published private(set) var isECGLoading = false
    @Published private(set) var isLoading = false
    @Published private(set) var hasRequestedAccess = false
    @Published var message: String?
    @Published var lastRefreshedAt: Date?

    private let repository = HealthKitRepository()
    var isHealthAvailable: Bool { repository.isAvailable }
    var insights: [HealthInsight] { InsightEngine.insights(readings: readings, sleep: sleep) }

    /// True only when this invocation completed the HealthKit authorization request.
    /// This does not indicate which read permissions the user granted.
    @discardableResult
    func connectAndRefresh() async -> Bool {
        guard !isLoading, repository.isAvailable else { return false }
        do {
            try await repository.requestAccess()
            hasRequestedAccess = true
            await refresh()
            return true
        } catch {
            message = "健康访问请求失败：\(error.localizedDescription)"
            return false
        }
    }

    func refresh() async {
        guard !isLoading, repository.isAvailable else { return }
        isLoading = true
        defer { isLoading = false }
        // Priority metrics first. Never substitute manufactured readings for missing records.
        let priority = ["heartRate", "restingHeartRate", "hrv", "oxygenSaturation", "respiratoryRate",
                        "sleepingWristTemperature", "systolic", "diastolic", "bloodGlucose"]
        let ordered = HealthCatalog.all.sorted {
            (priority.firstIndex(of: $0.id) ?? Int.max) < (priority.firstIndex(of: $1.id) ?? Int.max)
        }
        var newReadings: [String: MetricReading] = [:]
        var failures: [String] = []
        for metric in ordered {
            do {
                if let reading = try await repository.reading(metric) {
                    newReadings[metric.id] = reading
                }
            } catch {
                // A thrown query is a read error. A denied read and no record
                // can look identical by HealthKit design, so they stay out.
                failures.append(metric.id)
            }
        }
        readings = newReadings
        failedMetricIDs = failures
        let nightIDs = ["oxygenSaturation", "respiratoryRate", "sleepingWristTemperature", "appleSleepingBreathingDisturbances"]
        do {
            let intervals = try await repository.sleepIntervals()
            sleep = intervals.isEmpty ? nil : SleepCalculator.summarize(intervals)
            sleepWindow = SleepSession.window(from: intervals)
            var nights: [String: MetricReading] = [:]
            if let window = sleepWindow {
                for id in nightIDs {
                    if let metric = HealthCatalog.byID[id],
                       let reading = try? await repository.reading(metric, in: window) {
                        nights[id] = reading
                    }
                }
            }
            nightReadings = nights
        } catch {
            sleep = nil
            sleepWindow = nil
            nightReadings = [:]
        }
        ecgs = (try? await repository.ecgSummaries()) ?? []
        heartEvents = (try? await repository.heartEvents()) ?? []
        lastRefreshedAt = .now
    }

    func loadECGVoltage(for id: UUID) async {
        guard ecgVoltages[id] == nil, !isECGLoading else { return }
        isECGLoading = true
        defer { isECGLoading = false }
        do { ecgVoltages[id] = try await repository.ecgVoltagePoints(id: id) }
        catch { message = "读取 ECG 波形失败：\(error.localizedDescription)" }
    }

    func loadTrend(for metric: HealthMetric, days: Int = 30) async {
        do { trends[metric.id] = try await repository.trend(metric, days: days) }
        catch { message = "读取趋势失败：\(error.localizedDescription)" }
    }

    func saveWeight(_ weight: Double) async -> Bool { await save { try await repository.saveWeight(weight) } }
    func saveGlucose(_ glucose: Double) async -> Bool { await save { try await repository.saveGlucose(glucose) } }
    func savePressure(systolic: Double, diastolic: Double) async -> Bool {
        await save { try await repository.saveBloodPressure(systolic: systolic, diastolic: diastolic) }
    }

    private func save(_ operation: () async throws -> Void) async -> Bool {
        do {
            try await operation()
            message = "测量已写入 Apple 健康。"
            await refresh()
            return true
        } catch { message = "保存失败：\(error.localizedDescription)"; return false }
    }
}
