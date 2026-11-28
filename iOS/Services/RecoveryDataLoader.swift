import Foundation
import HealthKit
import HealthCore

/// Builds the Build 28 recovery models from HealthKit records plus the
/// user's own stored inputs (sleep target, energy/fatigue ratings,
/// workout RPE). Read-only against HealthKit; never fabricates values.
///
/// Coverage (Build 28 P0-1): only days the user explicitly verified in
/// RecoveryInputsStore count as confirmed (see RecoveryLoadReport).
/// A sleep interval never confirms a full sleep day, and a workout or
/// step count never confirms an activity day. Unverified days keep nil
/// sleep / training values; missing data is never zero-filled. A
/// verified day with no workouts is a genuine rest day (load 0).
/// The UI labels every figure "按已同步记录" and never claims a day
/// is complete.
@MainActor
struct RecoveryDataLoader {
    let repository: HealthKitRepository
    let inputs: RecoveryInputsStore

    /// One autonomic snapshot for asOf's day: resting-context SDNN and
    /// resting heart rate against the 30-day personal baseline, plus the
    /// raw-sample diagnostics behind the snapshot.
    func loadAutonomic(asOf: Date = Date()) async throws
        -> (day: AutonomicRecoveryDay, diagnostics: RawSampleDiagnostics) {
        let raw = try await rawSamples(asOf: asOf, windowDays: 30)
        let day = AutonomicRecoveryDay(restingSDNN: raw.sdnn, restingBPM: raw.bpm, asOf: asOf)
        return (day, raw.diagnostics)
    }

    /// Week report + journal + rated workouts + today's autonomic
    /// snapshot, from a single set of HealthKit reads. The journal needs
    /// one autonomic snapshot per report day, built from the same samples.
    func loadRecovery(period: RecoveryLoadReport.Period = .week, asOf: Date = Date()) async throws
        -> (report: RecoveryLoadReport, journal: RecoveryJournal, workouts: [RatedWorkout],
            autonomicToday: AutonomicRecoveryDay, workoutTypeNames: [UUID: String],
            followUps: [PostWorkoutFollowUp], diagnostics: RawSampleDiagnostics) {
        let calendar = Calendar.current
        // Resting filter needs workout intervals over the whole raw
        // window (period + 30 calendar days), not just the report
        // window, so fetch them once here and reuse them for the
        // report below.
        let window = SourcedSampleWindow.window(days: period.rawValue + 30, asOf: asOf, calendar: calendar)
        let filterWorkouts = try await repository.workouts(from: window.from, through: asOf)
        let (sdnn, bpm, diagnostics) = try await rawSamples(asOf: asOf, windowDays: period.rawValue + 30,
                                                             workouts: filterWorkouts)
        let from = calendar.date(byAdding: .day, value: -(period.rawValue + 2), to: calendar.startOfDay(for: asOf))!
        let intervals = try await repository.sleepIntervals(from: from, through: asOf)
        let rawWorkouts = filterWorkouts.filter { $0.end > from }
        let workouts = rawWorkouts.map {
            RatedWorkout(id: $0.id, start: $0.start, end: $0.end, activeMinutes: $0.activeMinutes,
                         exertion: inputs.exertion(for: $0.id))
        }
        // Build 28 P0-1: only days the user explicitly verified are
        // confirmed. Sleep intervals, workouts and step counts never
        // confirm a day on their own.
        let today = calendar.startOfDay(for: asOf)
        let reportDays = (0..<period.rawValue).compactMap { offset in
            calendar.date(byAdding: .day, value: offset - period.rawValue, to: today)
        }
        let sleepDays = Set(reportDays.filter { inputs.isSleepVerified(on: $0) })
        let workoutDays = Set(reportDays.filter { inputs.isActivityVerified(on: $0) })
        let report = RecoveryLoadReport(period: period, asOf: asOf, targetMinutes: inputs.sleepTargetMinutes,
                                        sleep: intervals, confirmedSleepDays: sleepDays,
                                        workouts: workouts, confirmedWorkoutDays: workoutDays)
        var snapshots: [AutonomicRecoveryDay] = []
        for day in report.days {
            let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: day.date) ?? day.date
            snapshots.append(AutonomicRecoveryDay(restingSDNN: sdnn, restingBPM: bpm, asOf: endOfDay))
        }
        let journal = RecoveryJournal(report: report, autonomic: snapshots,
                        energy: inputs.energyPoints(), fatigue: inputs.fatiguePoints())
        let autonomicToday = AutonomicRecoveryDay(restingSDNN: sdnn, restingBPM: bpm, asOf: asOf)
        let types = (try? await repository.workoutActivityTypes(from: from, through: asOf)) ?? [:]
        let workoutTypeNames = Dictionary(uniqueKeysWithValues: types.map { ($0.key, Self.workoutTypeName($0.value)) })
        let followUps = workouts.compactMap { PostWorkoutFollowUp(workout: $0, otherWorkouts: workouts, journal: journal, asOf: asOf) }
        return (report, journal, workouts, autonomicToday, workoutTypeNames, followUps, diagnostics)
    }

    /// Chinese display name for a HealthKit workout type. Unknown types
    /// stay "其他运动"; the name never affects any calculation.
    static func workoutTypeName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: return "跑步"
        case .walking: return "步行"
        case .cycling: return "骑行"
        case .swimming: return "游泳"
        case .yoga: return "瑜伽"
        case .hiking: return "徒步"
        case .elliptical: return "椭圆机"
        case .rowing: return "划船"
        case .stairClimbing: return "爬楼"
        case .dance: return "舞蹈"
        case .basketball: return "篮球"
        case .tennis: return "网球"
        case .badminton: return "羽毛球"
        case .soccer: return "足球"
        case .tableTennis: return "乒乓球"
        case .golf: return "高尔夫"
        case .crossTraining: return "交叉训练"
        case .jumpRope: return "跳绳"
        case .pilates: return "普拉提"
        case .taiChi: return "太极"
        case .martialArts: return "武术"
        case .coreTraining: return "核心训练"
        case .flexibility: return "拉伸"
        case .cooldown: return "放松"
        case .functionalStrengthTraining: return "功能性力量训练"
        case .traditionalStrengthTraining: return "传统力量训练"
        default: return "其他运动"
        }
    }

    /// Raw SDNN (ms) and resting heart rate samples in the calendar-day
    /// window ending at asOf, oldest first, plus the diagnostics for
    /// everything the window or the resting filter dropped. Daily
    /// aggregates cannot serve the hourly distribution or the 30-day
    /// baseline the recovery models need.
    ///
    /// Window: `windowDays` calendar days, from the start of the day
    /// `windowDays` days before asOf to asOf - never a fixed number of
    /// seconds, so a daylight-saving transition cannot shift the window
    /// by an hour. Resting-context filtering happens before the samples
    /// reach AutonomicRecoveryDay: watch sources only, no workout
    /// overlap, and no sample ending after asOf. Limit truncation,
    /// future samples and conflicting duplicate UUIDs are counted in
    /// the returned diagnostics instead of failing the load.
    private func rawSamples(asOf: Date, windowDays: Int, workouts: [RatedWorkout]? = nil) async throws
        -> (sdnn: [TrendPoint], bpm: [TrendPoint], diagnostics: RawSampleDiagnostics) {
        guard let hrv = HealthCatalog.byID["hrv"], let rhr = HealthCatalog.byID["restingHeartRate"] else {
            return ([], [], .empty)
        }
        let window = SourcedSampleWindow.window(days: windowDays, asOf: asOf, calendar: .current)
        let filterWorkouts: [RatedWorkout]
        if let workouts {
            filterWorkouts = workouts
        } else {
            filterWorkouts = try await repository.workouts(from: window.from, through: asOf)
        }
        let workoutIntervals = filterWorkouts.map { DateInterval(start: $0.start, end: $0.end) }
        let (sdnnSourced, sdnnTruncated) = try await repository.sourcedSamples(
            hrv, from: window.from, through: window.through, limit: 2000)
        let (bpmSourced, bpmTruncated) = try await repository.sourcedSamples(
            rhr, from: window.from, through: window.through, limit: 2000)
        let sdnn = selectRestingSamples(sdnnSourced, workouts: workoutIntervals, asOf: asOf, truncated: sdnnTruncated)
        let bpm = selectRestingSamples(bpmSourced, workouts: workoutIntervals, asOf: asOf, truncated: bpmTruncated)
        return (sdnn.samples.map(\.trendPoint), bpm.samples.map(\.trendPoint),
                sdnn.diagnostics.merging(bpm.diagnostics))
    }
}
