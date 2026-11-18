import Foundation

/// 自研生理负荷信号估算（不是 Bevel 的 Stress Score，Bevel 算法未公开）。
/// 输入全部来自 HealthKit 已有记录；HealthKit 没有直接的压力类型。
/// 全程只说“生理负荷信号”“估算”，不说压力诊断、情绪判断或医疗建议。
/// 不制造、不写死、不补零任何健康数值：缺数据就是缺数据。
///
/// 估算规则（透明可审计，阈值见下）：
/// - HRV（当日中位数）低于个人基线 15% 以上 +1，高于基线 15% 以上 -1。
///   恰好 15% 不触发（严格大于才记分）。
/// - 静息心率高于个人基线 7% 以上 +1，低于基线 7% 以上 -1。
///   恰好 7% 不触发。
/// - 静息时段（该小时步数 < 100 且活动能量 < 20 kcal）心率中位数高于
///   静息心率 +15 次/分 +1；活动时段的心率升高记为“活动可解释”，
///   不加分，并写入 drivers。
/// - 呼吸频率高于 20 次/分 +1（本估算没有呼吸频率基线参数，无基线时
///   同样只用 20 次/分这一条，且置信度降档）。
/// - 汇总：points <= -1 为 low，0...1 为 moderate，>= 2 为 elevated。
/// - 当日有效输入 < 3 项（HRV、静息心率、心率、呼吸频率中有值的项），
///   或 24 小时内 HRV 样本小时数为 0 且无静息心率时，返回 insufficient。
/// - 无基线时置信度最高 medium，并注明“无个人基线，仅作当日相对参考”。
public struct StressHourInput: Equatable, Sendable {
    public let hourStart: Date
    public let hrvMedian: Double?
    public let restingHeartRate: Double?
    public let heartRateMedian: Double?
    public let respiratoryRateMedian: Double?
    public let steps: Double
    public let activeEnergyKcal: Double

    public init(hourStart: Date, hrvMedian: Double? = nil, restingHeartRate: Double? = nil,
                heartRateMedian: Double? = nil, respiratoryRateMedian: Double? = nil,
                steps: Double = 0, activeEnergyKcal: Double = 0) {
        self.hourStart = hourStart
        self.hrvMedian = hrvMedian
        self.restingHeartRate = restingHeartRate
        self.heartRateMedian = heartRateMedian
        self.respiratoryRateMedian = respiratoryRateMedian
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
    }

    /// 该小时是否有任一生理信号输入（步数与活动能量不算生理信号）。
    public var hasPhysiologicalInput: Bool {
        return hrvMedian != nil || restingHeartRate != nil || heartRateMedian != nil || respiratoryRateMedian != nil
    }

    /// 静息时段：步数与活动能量都很低的小时。
    public var isRestingHour: Bool {
        return steps < 100 && activeEnergyKcal < 20
    }
}

public enum StressLevel: String, Equatable, Sendable {
    case low = "生理负荷信号较低"
    case moderate = "生理负荷信号中等"
    case elevated = "生理负荷信号偏高"
    case insufficient = "数据不足"
}

public enum StressConfidence: String, Equatable, Sendable {
    case low = "低"
    case medium = "中"
    case high = "高"
}

public struct StressEstimate: Equatable, Sendable {
    public let level: StressLevel
    public let confidence: StressConfidence
    public let points: Int
    public let drivers: [String]
    public let coveredInputs: Int
    public let totalInputs: Int
    public let hasBaseline: Bool

    public init(level: StressLevel, confidence: StressConfidence, points: Int,
                drivers: [String], coveredInputs: Int, totalInputs: Int, hasBaseline: Bool) {
        self.level = level
        self.confidence = confidence
        self.points = points
        self.drivers = drivers
        self.coveredInputs = coveredInputs
        self.totalInputs = totalInputs
        self.hasBaseline = hasBaseline
    }
}

public enum StressCalculator {
    /// 当日汇总估算。hrvBaseline / restingBaseline 为个人基线（30 天趋势，
    /// 需至少 7 天数据才算有效基线）；任一缺失都视为无完整基线。
    public static func estimate(hours: [StressHourInput], hrvBaseline: Double?, restingBaseline: Double?) -> StressEstimate {
        let totalInputs = 4
        let hrvValues = hours.compactMap { $0.hrvMedian }
        let restingValues = hours.compactMap { $0.restingHeartRate }
        let heartRateValues = hours.compactMap { $0.heartRateMedian }
        let respiratoryValues = hours.compactMap { $0.respiratoryRateMedian }
        var coveredInputs = 0
        if hrvValues.isEmpty == false { coveredInputs += 1 }
        if restingValues.isEmpty == false { coveredInputs += 1 }
        if heartRateValues.isEmpty == false { coveredInputs += 1 }
        if respiratoryValues.isEmpty == false { coveredInputs += 1 }

        let hasBaseline = hrvBaseline != nil && restingBaseline != nil
        let hrvHours = hrvValues.count
        let hasRestingHeartRate = restingValues.isEmpty == false
        if coveredInputs < 3 || (hrvHours == 0 && hasRestingHeartRate == false) {
            return StressEstimate(
                level: .insufficient, confidence: .low, points: 0,
                drivers: ["有效输入仅 \(coveredInputs)/\(totalInputs) 项，数据不足"],
                coveredInputs: coveredInputs, totalInputs: totalInputs, hasBaseline: hasBaseline
            )
        }

        var points = 0
        var drivers: [String] = []

        if let baseline = hrvBaseline, baseline > 0, let dailyHRV = median(hrvValues) {
            let change = (dailyHRV - baseline) / baseline
            if change < -0.15 {
                points += 1
                let percent = Int(((baseline - dailyHRV) / baseline * 100).rounded())
                drivers.append("HRV 低于个人基线 \(percent)%")
            } else if change > 0.15 {
                points -= 1
                let percent = Int(((dailyHRV - baseline) / baseline * 100).rounded())
                drivers.append("HRV 高于个人基线 \(percent)%")
            }
        }

        if let baseline = restingBaseline, baseline > 0, let dailyResting = median(restingValues) {
            let change = (dailyResting - baseline) / baseline
            if change > 0.07 {
                points += 1
                let percent = Int(((dailyResting - baseline) / baseline * 100).rounded())
                drivers.append("静息心率高于个人基线 \(percent)%")
            } else if change < -0.07 {
                points -= 1
                let percent = Int(((baseline - dailyResting) / baseline * 100).rounded())
                drivers.append("静息心率低于个人基线 \(percent)%")
            }
        }

        let restingReference = median(restingValues)
        var restingElevatedHours = 0
        var activityExplainedHours = 0
        for hour in hours {
            guard let heartRate = hour.heartRateMedian else { continue }
            let reference = hour.restingHeartRate ?? restingReference
            guard let reference else { continue }
            if heartRate > reference + 15 {
                if hour.isRestingHour {
                    restingElevatedHours += 1
                } else {
                    activityExplainedHours += 1
                }
            }
        }
        if restingElevatedHours > 0 {
            points += 1
            drivers.append("静息时段心率高于静息心率 15 次/分以上（\(restingElevatedHours) 小时）")
        }
        if activityExplainedHours > 0 {
            drivers.append("活动时段心率升高 \(activityExplainedHours) 小时，由活动可解释，不计入负荷信号")
        }

        var respiratoryHighHours = 0
        for hour in hours {
            if let rate = hour.respiratoryRateMedian, rate > 20 {
                respiratoryHighHours += 1
            }
        }
        if respiratoryHighHours > 0 {
            points += 1
            drivers.append("呼吸频率高于 20 次/分（\(respiratoryHighHours) 小时）")
        }

        if hasBaseline == false {
            drivers.append("无个人基线，仅作当日相对参考")
        }

        let level: StressLevel
        if points <= -1 {
            level = .low
        } else if points <= 1 {
            level = .moderate
        } else {
            level = .elevated
        }
        if drivers.isEmpty {
            drivers.append("当日生理信号与个人基线接近，无明显负荷驱动因素")
        }

        let confidence: StressConfidence
        if hasBaseline == false {
            confidence = .medium
        } else if coveredInputs >= 3 {
            confidence = .high
        } else {
            confidence = .medium
        }

        return StressEstimate(
            level: level, confidence: confidence, points: points,
            drivers: drivers, coveredInputs: coveredInputs,
            totalInputs: totalInputs, hasBaseline: hasBaseline
        )
    }

    /// 逐小时级别。输入按 hourStart 排序返回；有数据的小时给级别，
    /// 无数据的小时给 nil 表示缺口，不补零。
    /// 注意：本方法没有基线参数，逐小时级别只用小时内绝对规则
    /// （静息时段心率高于静息心率 +15 次/分、呼吸频率 > 20 次/分）；
    /// 与基线比较的 HRV / 静息心率驱动只在当日汇总 estimate 里计算。
    public static func hourlyLevels(hours: [StressHourInput]) -> [(hourStart: Date, level: StressLevel?)] {
        let sorted = hours.sorted { $0.hourStart < $1.hourStart }
        return sorted.map { hour in
            guard hour.hasPhysiologicalInput else {
                return (hourStart: hour.hourStart, level: nil)
            }
            var points = 0
            if hour.isRestingHour {
                if let heartRate = hour.heartRateMedian, let resting = hour.restingHeartRate {
                    if heartRate > resting + 15 {
                        points += 1
                    }
                }
            }
            if let rate = hour.respiratoryRateMedian, rate > 20 {
                points += 1
            }
            // 无基线可比的逐小时级别只有“偏高 / 中等”两档：单项驱动
            // 不足以定为偏高，无驱动也不足以定为较低（较低只由当日
            // 汇总里 HRV / 静息心率高出基线反向驱动得出）。
            let level: StressLevel = points >= 2 ? .elevated : .moderate
            return (hourStart: hour.hourStart, level: level)
        }
    }

    /// 小型中位数 helper（不改 BaselineAnalyzer，其 median 为 private）。
    public static func median(_ values: [Double]) -> Double? {
        let numbers = values.filter { $0.isFinite }.sorted()
        guard numbers.isEmpty == false else { return nil }
        let middle = numbers.count / 2
        if numbers.count.isMultiple(of: 2) {
            return (numbers[middle - 1] + numbers[middle]) / 2
        }
        return numbers[middle]
    }
}
