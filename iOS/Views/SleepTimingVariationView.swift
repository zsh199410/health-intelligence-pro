import SwiftUI
import HealthCore

struct SleepTimingVariationView: View {
    @State private var result: SleepTimingVariation?
    @State private var error = false
    @State private var zone = ""
    private let repository = HealthKitRepository()

    var body: some View {
        List {
            Section("近七个完整日 · 按醒来日期归组") {
                if error {
                    Text("读取睡眠记录失败，请解锁设备后下拉重试。")
                } else if let result {
                    LabeledContent("有记录天数", value: "\(result.observedDays) / 7")
                    LabeledContent("可比较的相邻日", value: "\(result.adjacentPairs) 对")
                    if let onset = result.medianOnsetChange, let wake = result.medianWakeChange {
                        LabeledContent("入睡时刻变动中位数", value: "\(Int(onset.rounded())) 分钟")
                        LabeledContent("醒来时刻变动中位数", value: "\(Int(wake.rounded())) 分钟")
                    } else {
                        Text("至少需要两个相邻日期的睡眠记录。")
                    }
                } else {
                    ProgressView("读取睡眠记录")
                }
            }
            Section("统计方法") {
                Text("以分期记录的首末睡眠样本估计入睡与醒来时刻。两个睡眠样本相隔至少两小时即分段，每天取累计睡眠最长的一段。分段作息或记录缺失会影响结果。")
                Text("仅比较相邻日期，按当前时区的钟表时刻取最短时差。旅行时原记录地点的当地时间可能不同。")
                if !zone.isEmpty { LabeledContent("统计时区", value: zone) }
            }
        }
        .navigationTitle("睡眠时间规律")
        .task { await load() }
        .refreshable { await load() }
    }

    @MainActor private func load() async {
        let calendar = Calendar.current
        let now = Date()
        let start = SleepTimingVariation.reportStart(endingAt: now, calendar: calendar)
        // Include the preceding sleep onset for the earliest eligible wake day.
        let from = calendar.date(byAdding: .day, value: -2, to: start)!
        do {
            let intervals = try await repository.sleepIntervals(from: from, through: now)
            guard !Task.isCancelled else { return }
            zone = calendar.timeZone.identifier
            result = SleepTimingVariation.evaluate(intervals, endingAt: now, calendar: calendar)
            error = false
        } catch {
            guard !Task.isCancelled else { return }
            result = nil
            error = true
        }
    }
}
