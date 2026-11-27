import Foundation
import HealthKit
import HealthCore

/// Builds the Build 27 recovery models from HealthKit records plus the
/// user's own stored inputs (sleep target, energy/fatigue ratings,
/// workout RPE). Read-only against HealthKit; never fabricates values.
///
/// Coverage: HealthKit alone cannot prove a day is complete (see
/// RecoveryLoadReport). A past day counts as confirmed for a type when
/// at least one record of that type falls in the day's window; for
/// workouts, a past day with step samples but no workout counts as a
/// confirmed rest day. The UI labels every figure "按已同步记录" and
/// never claims a day is complete.
@MainActor
struct RecoveryDataLoader {
    let repository: HealthKitRepository
    let inputs: RecoveryInputsStore

    /// One autonomic snapshot for asOf's day: resting-context SDNN and
    /// resting heart rate against the 30-day personal baseline.
    func loadAutonomic(asOf: Date = Date()) async throws -> AutonomicRecoveryDay {
        let (sdnn, bpm) = try await rawSamples()
        return AutonomicRecoveryDay(restingSDNN: sdnn, restingBPM: bpm, asOf: asOf)
    }

    /// Week report + journal + rated workouts + today's autonomic
    /// snapshot, from a single set of HealthKit reads. The journal needs
    /// one autonomic snapshot per report day, built from the same samples.
    func loadRecovery(period: RecoveryLoadReport.Period = .week, asOf: Date = Date()) async throws
        -> (report: RecoveryLoadReport, journal: RecoveryJournal, workouts: [RatedWorkout],
            autonomicToday: AutonomicRecoveryDay, workoutTypeNames: [UUID: String],
            followUps: [PostWorkoutFollowUp]) {
        let calendar = Calendar.current
        let (sdnn, bpm) = try await rawSamples()
        let from = calendar.date(byAdding: .day, value: -(period.rawValue + 2), to: calendar.startOfDay(for: asOf))!
        let intervals = try await repository.sleepIntervals(from: from, through: asOf)
        let rawWorkouts = try await repository.workouts(from: from, through: asOf)
        let workouts = rawWorkouts.map {
            RatedWorkout(id: $0.id, start: $0.start, end: $0.end, activeMinutes: $0.activeMinutes,
                         exertion: inputs.exertion(for: $0.id))
        }
        // Step days mark the device as worn and syncing; a past day with
        // step samples but no workout is a confirmed rest day. If this
        // query throws, rest-day confirmation degrades silently and only
        // days with actual workouts count as confirmed.
        let steps = (try? await repository.trend(HealthCatalog.byID["stepCount"]!, days: period.rawValue + 2, endingAt: asOf)) ?? []
        let stepDays = Set(steps.map { calendar.startOfDay(for: $0.recordedAt) })
        let today = calendar.startOfDay(for: asOf)
        var sleepDays = Set<Date>()
        var workoutDays = Set<Date>()
        for offset in 0..<period.rawValue {
            guard let date = calendar.date(byAdding: .day, value: offset - period.rawValue, to: today) else { continue }
            let noon = calendar.date(bySettingHour: 12, minute: 0, second: 0, of: date)!
            let window = DateInterval(start: calendar.date(byAdding: .day, value: -1, to: noon)!, end: noon)
            if intervals.contains(where: { $0.start < window.end && $0.end > window.start }) {
                sleepDays.insert(date)
            }
            if workouts.contains(where: { calendar.startOfDay(for: $0.end) == date }) || stepDays.contains(date) {
                workoutDays.insert(date)
            }
        }
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
        return (report, journal, workouts, autonomicToday, workoutTypeNames, followUps)
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

    /// Raw SDNN (ms) and resting heart rate samples for the last 31 days,
    /// oldest first. Daily aggregates cannot serve the hourly distribution
    /// or the 30-day baseline the recovery models need.
    private func rawSamples() async throws -> (sdnn: [TrendPoint], bpm: [TrendPoint]) {
        guard let hrv = HealthCatalog.byID["hrv"], let rhr = HealthCatalog.byID["restingHeartRate"] else {
            return ([], [])
        }
        let sdnn = try await repository.samples(hrv, hours: 31 * 24, limit: 2000)
        let bpm = try await repository.samples(rhr, hours: 31 * 24, limit: 2000)
        return (sdnn, bpm)
    }
}
