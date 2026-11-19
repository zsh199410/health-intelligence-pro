import Foundation
import HealthKit

/// Each type is publicly available in HealthKit, but availability of *data* is
/// device-, region-, permission-, and user-dependent.
enum MetricGroup: String, CaseIterable, Identifiable {
    case heart = "心脏与循环"
    case breathing = "呼吸与睡眠相关"
    case body = "体征与身体"
    case mobility = "行动与活动"
    case environment = "环境与其他"
    var id: String { rawValue }
}

enum MetricAggregation { case latest, sumToday }

struct HealthMetric: Identifiable {
    let id: String
    let name: String
    let symbol: String
    let identifier: HKQuantityTypeIdentifier
    let unit: HKUnit
    let unitText: String
    let group: MetricGroup
    let decimals: Int
    let multiplier: Double
    let aggregation: MetricAggregation

    init(_ id: String, _ name: String, _ symbol: String, _ identifier: HKQuantityTypeIdentifier,
         _ unit: HKUnit, _ unitText: String, _ group: MetricGroup,
         decimals: Int = 1, multiplier: Double = 1, aggregation: MetricAggregation = .latest) {
        self.id = id; self.name = name; self.symbol = symbol; self.identifier = identifier
        self.unit = unit; self.unitText = unitText; self.group = group
        self.decimals = decimals; self.multiplier = multiplier; self.aggregation = aggregation
    }

    var quantityType: HKQuantityType { HKObjectType.quantityType(forIdentifier: identifier)! }
    func display(_ value: Double) -> String { String(format: "%.*f", decimals, value) }
}

enum HealthCatalog {
    static let pulseUnit = HKUnit.count().unitDivided(by: .minute())
    static let mgdl = HKUnit.gramUnit(with: .milli).unitDivided(by: .literUnit(with: .deci))
    static let mlkgmin = HKUnit.literUnit(with: .milli)
        .unitDivided(by: .gramUnit(with: .kilo)).unitDivided(by: .minute())

    static let all: [HealthMetric] = [
        .init("atrialFibrillationBurden", "房颤负荷（系统估计）", "waveform.path.ecg", .atrialFibrillationBurden, .percent(), "%", .heart, multiplier: 100),
        .init("heartRateRecoveryOneMinute", "一分钟心率恢复", "heart.text.clipboard.fill", .heartRateRecoveryOneMinute, pulseUnit, "次/分", .heart),
        .init("appleWalkingSteadiness", "步行稳定性", "figure.walk", .appleWalkingSteadiness, .percent(), "%", .mobility, multiplier: 100),
        .init("heartRate", "心率", "heart.fill", .heartRate, pulseUnit, "次/分", .heart, decimals: 0),
        .init("restingHeartRate", "静息心率", "heart.text.square", .restingHeartRate, pulseUnit, "次/分", .heart, decimals: 0),
        .init("hrv", "HRV（SDNN）", "waveform.path.ecg", .heartRateVariabilitySDNN, .secondUnit(with: .milli), "毫秒", .heart),
        .init("walkingHeartRateAverage", "步行平均心率", "figure.walk", .walkingHeartRateAverage, pulseUnit, "次/分", .heart, decimals: 0),
        .init("oxygenSaturation", "血氧", "lungs.fill", .oxygenSaturation, .percent(), "%", .breathing, multiplier: 100),
        .init("respiratoryRate", "呼吸频率", "wind", .respiratoryRate, pulseUnit, "次/分", .breathing),
        .init("sleepingWristTemperature", "睡眠腕温", "thermometer", .appleSleepingWristTemperature, .degreeCelsius(), "℃", .body),
        .init("bodyTemperature", "体温记录", "thermometer.medium", .bodyTemperature, .degreeCelsius(), "℃", .body),
        .init("systolic", "收缩压", "drop.fill", .bloodPressureSystolic, .millimeterOfMercury(), "mmHg", .heart, decimals: 0),
        .init("diastolic", "舒张压", "drop", .bloodPressureDiastolic, .millimeterOfMercury(), "mmHg", .heart, decimals: 0),
        .init("bloodGlucose", "血糖", "cross.vial", .bloodGlucose, mgdl, "mg/dL", .body, decimals: 0),
        .init("bodyMass", "体重", "scalemass.fill", .bodyMass, .gramUnit(with: .kilo), "kg", .body),
        .init("bodyMassIndex", "BMI", "person.crop.rectangle", .bodyMassIndex, .count(), "", .body),
        .init("bodyFatPercentage", "体脂率", "figure.arms.open", .bodyFatPercentage, .percent(), "%", .body, multiplier: 100),
        .init("leanBodyMass", "去脂体重", "figure.strengthtraining.traditional", .leanBodyMass, .gramUnit(with: .kilo), "kg", .body),
        .init("height", "身高", "ruler.fill", .height, .meter(), "m", .body, decimals: 2),
        .init("waistCircumference", "腰围", "circle.dotted", .waistCircumference, .meterUnit(with: .centi), "cm", .body),
        .init("dietaryWater", "今日饮水", "drop.fill", .dietaryWater, .literUnit(with: .milli), "毫升", .body, decimals: 0, aggregation: .sumToday),
        .init("dietaryEnergy", "今日饮食能量", "fork.knife", .dietaryEnergyConsumed, .kilocalorie(), "kcal", .body, decimals: 0, aggregation: .sumToday),
        .init("vo2Max", "心肺适能 VO₂max", "lungs", .vo2Max, mlkgmin, "mL/kg/min", .heart),
        .init("stepCount", "今日步数", "shoeprints.fill", .stepCount, .count(), "步", .mobility, decimals: 0, aggregation: .sumToday),
        .init("distanceWalkingRunning", "今日步行距离", "figure.walk.motion", .distanceWalkingRunning, .meterUnit(with: .kilo), "km", .mobility, aggregation: .sumToday),
        .init("activeEnergy", "今日活动能量", "flame.fill", .activeEnergyBurned, .kilocalorie(), "kcal", .mobility, decimals: 0, aggregation: .sumToday),
        .init("basalEnergy", "今日静息能量", "bolt.heart", .basalEnergyBurned, .kilocalorie(), "kcal", .mobility, decimals: 0, aggregation: .sumToday),
        .init("flightsClimbed", "今日爬楼层数", "stairs", .flightsClimbed, .count(), "层", .mobility, decimals: 0, aggregation: .sumToday),
        .init("walkingSpeed", "步行速度", "figure.walk.circle", .walkingSpeed, .meter().unitDivided(by: .second()), "m/s", .mobility),
        .init("walkingStepLength", "步长", "figure.walk", .walkingStepLength, .meterUnit(with: .centi), "cm", .mobility),
        .init("walkingAsymmetryPercentage", "步态不对称", "figure.walk.diamond", .walkingAsymmetryPercentage, .percent(), "%", .mobility, multiplier: 100),
        .init("walkingDoubleSupportPercentage", "双脚支撑时间比例", "figure.stand", .walkingDoubleSupportPercentage, .percent(), "%", .mobility, multiplier: 100),
        .init("sixMinuteWalkTestDistance", "六分钟步行距离", "figure.walk.motion", .sixMinuteWalkTestDistance, .meter(), "m", .mobility),
        .init("environmentalAudioExposure", "环境声音暴露", "ear.badge.waveform", .environmentalAudioExposure, .decibelAWeightedSoundPressureLevel(), "dB", .environment),
        .init("headphoneAudioExposure", "耳机声音暴露", "headphones", .headphoneAudioExposure, .decibelAWeightedSoundPressureLevel(), "dB", .environment),
        .init("timeInDaylight", "今日日照时间", "sun.max.fill", .timeInDaylight, .minute(), "分钟", .environment, decimals: 0, aggregation: .sumToday),
        .init("appleSleepingBreathingDisturbances", "夜间呼吸扰动", "waveform.path", .appleSleepingBreathingDisturbances, .count(), "次", .breathing)
    ]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
}
