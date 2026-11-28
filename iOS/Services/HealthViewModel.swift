import Foundation
import Combine
import HealthCore

@MainActor
final class HealthViewModel: ObservableObject {
    @Published private(set) var readings: [String: MetricReading] = [:]
    @Published private(set) var trends: [String: [TrendPoint]] = [:]
    @Published private(set) var sleep: SleepSummary?
    @Published private(set) var sleepSegments: [SleepInterval] = []
    /// Daily sleep totals for the past 7 calendar days, grouped by wake date.
    @Published private(set) var sleepHistory: [SleepHistoryDay] = []
    @Published private(set) var sleepHistoryFailed = false
    /// Seven-day sleep timing regularity, same evaluation as the detail page.
    @Published private(set) var sleepRegularity: SleepTimingVariation?
    @Published private(set) var sleepRegularityFailed = false
    @Published private(set) var sleepReadFailed = false
    @Published private(set) var failedNightMetricIDs: Set<String> = []
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
    @Published private(set) var ecgReadFailed = false
    @Published private(set) var ecgs: [ECGSummary] = []
    @Published private(set) var heartEvents: [HeartEvent] = []
    @Published private(set) var isLoading = false
    @Published private(set) var hasRequestedAccess = false
    @Published var message: String?
    @Published var lastRefreshedAt: Date?

    private let repository = HealthKitRepository()
    /// User-entered recovery inputs (sleep target, energy/fatigue ratings,
    /// workout RPE). Owned here so every recovery page shares one store.
    let recoveryInputs = RecoveryInputsStore()
    /// Today's autonomic snapshot (resting SDNN + resting heart rate
    /// against the 30-day personal baseline), nil until loaded.
    @Published private(set) var autonomicDay: AutonomicRecoveryDay?
    @Published private(set) var autonomicFailed = false
    /// Week load report and recovery journal, nil until loaded.
    @Published private(set) var recoveryReport: RecoveryLoadReport?
    @Published private(set) var recoveryJournal: RecoveryJournal?
    @Published private(set) var recoveryWorkouts: [RatedWorkout] = []
    @Published private(set) var recoveryWorkoutTypeNames: [UUID: String] = [:]
    @Published private(set) var recoveryFollowUps: [PostWorkoutFollowUp] = []
    @Published private(set) var recoveryFailed = false
    @Published private(set) var recoveryLoadedAt: Date?
    /// Raw-sample diagnostics for the resting-context SDNN / resting
    /// heart rate window behind `autonomicDay` (fetched, excluded,
    /// dropped and truncated counts, plus the verbatim sources), nil
    /// until loaded.
    @Published private(set) var rawSampleDiagnostics: RawSampleDiagnostics?
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
            let session = SleepSession.latest(from: intervals)
            var nights: [String: MetricReading] = [:]
            var nightFailures: Set<String> = []
            if let window = session?.window {
                for id in nightIDs {
                    guard let metric = HealthCatalog.byID[id] else { continue }
                    do {
                        nights[id] = try await repository.reading(metric, in: window)
                    } catch {
                        nightFailures.insert(id)
                    }
                }
            }
            sleep = session.map { SleepCalculator.summarize($0.intervals) }
            sleepWindow = session?.window
            sleepSegments = session.map { SleepCalculator.segments($0.intervals) } ?? []
            sleepReadFailed = false
            nightReadings = nights
            failedNightMetricIDs = nightFailures
        } catch {
            sleep = nil
            sleepWindow = nil
            sleepSegments = []
            sleepReadFailed = true
            nightReadings = [:]
            failedNightMetricIDs = []
        }
        do {
            ecgs = try await repository.ecgSummaries()
            ecgReadFailed = false
        } catch {
            ecgs = []
            ecgReadFailed = true
        }
        heartEvents = (try? await repository.heartEvents()) ?? []
        lastRefreshedAt = .now
    }

    func ecgWaveform(for id: UUID) async throws -> ECGWaveform? {
        try await repository.ecgWaveform(id: id)
    }

    func loadTrend(for metric: HealthMetric, days: Int = 30) async {
        do { trends[metric.id] = try await repository.trend(metric, days: days) }
        catch { message = "读取趋势失败：\(error.localizedDescription)" }
    }

    func loadSleepHistory(days: Int = 7) async {
        let calendar = Calendar.current
        let now = Date()
        let from = calendar.date(byAdding: .day, value: -(days + 1), to: calendar.startOfDay(for: now))!
        do {
            let intervals = try await repository.sleepIntervals(from: from, through: now)
            sleepHistory = SleepHistory.days(from: intervals, days: days, endingAt: now, calendar: calendar)
            sleepHistoryFailed = false
        } catch {
            sleepHistory = []
            sleepHistoryFailed = true
        }
    }

    func loadSleepRegularity() async {
        let calendar = Calendar.current
        let now = Date()
        let start = SleepTimingVariation.reportStart(endingAt: now, calendar: calendar)
        let from = calendar.date(byAdding: .day, value: -2, to: start)!
        do {
            let intervals = try await repository.sleepIntervals(from: from, through: now)
            sleepRegularity = SleepTimingVariation.evaluate(intervals, endingAt: now, calendar: calendar)
            sleepRegularityFailed = false
        } catch {
            sleepRegularity = nil
            sleepRegularityFailed = true
        }
    }

    /// Loads the Build 27 recovery models (today's autonomic snapshot,
    /// week load report, recovery journal, rated workouts). Called by the
    /// recovery pages on appear; refresh() keeps its existing scope.
    func loadRecovery() async {
        let loader = RecoveryDataLoader(repository: repository, inputs: recoveryInputs)
        do {
            let result = try await loader.loadRecovery()
            autonomicDay = result.autonomicToday
            rawSampleDiagnostics = result.diagnostics
            recoveryReport = result.report
            recoveryJournal = result.journal
            recoveryWorkouts = result.workouts
            recoveryWorkoutTypeNames = result.workoutTypeNames
            recoveryFollowUps = result.followUps
            recoveryFailed = false
            recoveryLoadedAt = .now
        } catch {
            autonomicDay = nil
            rawSampleDiagnostics = nil
            recoveryReport = nil
            recoveryJournal = nil
            recoveryWorkouts = []
            recoveryWorkoutTypeNames = [:]
            recoveryFollowUps = []
            recoveryFailed = true
        }
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
