import SwiftUI
import Charts
import HealthCore

struct SleepView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var plotHeight = 148.0
    @State private var sleepTargetMinutes: Double = 480
    @State private var hasSleepTarget = false
    private let dayStyle = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))
    private let stages: [SleepStage] = [.awake, .rem, .core, .deep, .unspecified]
    private let dateStyle = Date.FormatStyle.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("睡眠，是身体的修复时间")
                        .font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                    if let summary = health.sleep, let window = health.sleepWindow {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("最近一次睡眠").font(.headline)
                            Text("\(summary.totalAsleepMinutes / 60) 小时 \(summary.totalAsleepMinutes % 60) 分")
                                .font(.largeTitle.bold()).monospacedDigit()
                            Text("\(window.lowerBound.formatted(dateStyle)) 至 \(window.upperBound.formatted(dateStyle))")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                        HealthCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("睡眠分期").font(.headline)
                                Chart(health.sleepSegments, id: \.start) { segment in
                                    BarMark(
                                        xStart: .value("开始", segment.start),
                                        xEnd: .value("结束", segment.end),
                                        y: .value("分期", segment.stage.rawValue)
                                    )
                                    .foregroundStyle(HealthTheme.stageColor(segment.stage))
                                    .accessibilityLabel(segment.stage.rawValue)
                                    .accessibilityValue("\(segment.start.formatted(dateStyle)) 至 \(segment.end.formatted(dateStyle))")
                                }
                                .chartXScale(domain: window)
                                .chartYScale(domain: stages.map(\.rawValue))
                                .chartXAxis {
                                    AxisMarks(values: [window.lowerBound, window.upperBound]) {
                                        AxisValueLabel(format: .dateTime.hour().minute().locale(Locale(identifier: "zh_CN")))
                                    }
                                }
                                .frame(height: plotHeight)
                                ForEach(stages, id: \.self) { stage in
                                    LabeledContent(stage.rawValue, value: "\(summary.minutesByStage[stage] ?? 0) 分钟")
                                }
                                Text("空白时段缺少分期记录。重叠区间只计算一次，多来源分期冲突可能影响结果。")
                                    .font(.footnote).foregroundStyle(HealthTheme.muted)
                            }
                        }
                        Text("夜间生命体征").font(.headline)
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                            ForEach(["oxygenSaturation", "respiratoryRate", "sleepingWristTemperature", "appleSleepingBreathingDisturbances"], id: \.self) { id in
                                if let metric = HealthCatalog.byID[id] {
                                    NavigationLink {
                                        NightReadingDetail(metric: metric)
                                    } label: {
                                        MetricTile(metric: metric, reading: health.nightReadings[id],
                                                   emptyText: health.failedNightMetricIDs.contains(id) ? "读取失败" : "无夜间记录")
                                    }.buttonStyle(.plain)
                                }
                            }
                        }
                    } else {
                        sleepStatus
                    }
                    sleepHistorySection
                    sleepRegularitySection
                    sleepGoalSection
                    NavigationLink("近七日睡眠时间规律") {
                        SleepTimingVariationView()
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("睡眠健康")
            .task {
                await health.loadSleepHistory()
                await health.loadSleepRegularity()
                hasSleepTarget = health.recoveryInputs.sleepTargetMinutes != nil
                sleepTargetMinutes = Double(health.recoveryInputs.sleepTargetMinutes ?? 480)
                await health.loadRecovery()
            }
            .refreshable {
                await health.refresh()
                await health.loadSleepHistory()
                await health.loadSleepRegularity()
                await health.loadRecovery()
            }
        }
    }

    @ViewBuilder private var sleepGoalSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "睡眠目标与短缺", subtitle: "目标是你自己定的；短缺只按你已核实的日子算")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if hasSleepTarget {
                        Stepper("每晚睡眠目标 \(hoursText(sleepTargetMinutes))", onIncrement: { adjustTarget(by: 30) }, onDecrement: { adjustTarget(by: -30) })
                    } else {
                        Text("还没有设置每晚睡眠目标，设置后这里会显示每天的短缺。")
                            .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        Button("设置目标：8 小时") {
                            hasSleepTarget = true
                            sleepTargetMinutes = 480
                            health.recoveryInputs.setSleepTarget(minutes: 480)
                            Task { await health.loadRecovery() }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    if let report = health.recoveryReport {
                        ForEach(report.days.reversed(), id: \.date) { day in
                            sleepGoalDayRow(day)
                            if day.date != report.days.first?.date { Divider() }
                        }
                        sleepShortfallTotals(report)
                    }
                    Text("短缺 = 目标 − 实际睡眠；睡够目标不记负数；未核实的日子不计入短缺。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func sleepGoalDayRow(_ day: RecoveryLoadReport.Day) -> some View {
        let verified = health.recoveryInputs.isSleepVerified(on: day.date)
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.date.formatted(dayStyle))
                Spacer()
                Text(dayText(day))
            }
            .font(.subheadline)
            HStack(spacing: 8) {
                Text(verified ? "已核实" : "未核实")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(verified ? HealthTheme.ink : HealthTheme.muted)
                    .accessibilityLabel(verified ? "睡眠数据已核实" : "睡眠数据未核实")
                Spacer()
                if verified {
                    Button("取消核实") {
                        health.recoveryInputs.unverifySleep(on: day.date)
                        Task { await health.loadRecovery() }
                    }
                    .font(.caption)
                    .accessibilityLabel("取消核实\(day.date.formatted(dayStyle))的睡眠数据")
                } else if day.latestSleepSampleEnd != nil {
                    Button("确认数据完整") {
                        health.recoveryInputs.verifySleep(on: day.date)
                        Task { await health.loadRecovery() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("确认\(day.date.formatted(dayStyle))的睡眠数据完整")
                }
            }
        }
    }

    @ViewBuilder private func sleepShortfallTotals(_ report: RecoveryLoadReport) -> some View {
        let shortfalls = report.days.compactMap(\.shortfallMinutes)
        if let total = report.totalShortfallMinutes {
            Text("近 7 天累计短缺 \(hoursText(Double(total)))")
                .font(.subheadline.weight(.semibold))
        } else if !shortfalls.isEmpty {
            Text("局部总和（\(shortfalls.count)/7 天有值）：\(hoursText(shortfalls.reduce(0, +)))")
                .font(.subheadline.weight(.semibold))
            Text("有 \(report.days.filter { $0.shortfallMinutes == nil }.count) 天短缺未知，无法汇总完整总和。")
                .font(.subheadline).foregroundStyle(HealthTheme.muted)
        } else {
            Text("有 \(report.days.filter { $0.shortfallMinutes == nil }.count) 天短缺未知，无法汇总累计短缺。")
                .font(.subheadline).foregroundStyle(HealthTheme.muted)
        }
    }

    private func adjustTarget(by delta: Double) {
        let next = min(720, max(240, sleepTargetMinutes + delta))
        sleepTargetMinutes = next
        health.recoveryInputs.setSleepTarget(minutes: next)
        Task { await health.loadRecovery() }
    }

    private func hoursText(_ minutes: Double) -> String {
        let total = Int(minutes)
        if total % 60 == 0 { return "\(total / 60) 小时" }
        return "\(total / 60) 小时 \(total % 60) 分钟"
    }

    private func dayText(_ day: RecoveryLoadReport.Day) -> String {
        guard let minutes = day.sleepMinutes else {
            return day.latestSleepSampleEnd == nil ? "无记录" : "有记录，未核实"
        }
        let slept = hoursText(Double(minutes))
        guard let shortfall = day.shortfallMinutes else { return "睡了 \(slept)" }
        if shortfall > 0 {
            return "睡了 \(slept)，短缺 \(shortfall) 分钟"
        }
        return "睡了 \(slept)，已达标"
    }

    @ViewBuilder private var sleepStatus: some View {
        if !health.isHealthAvailable {
            EmptyHealthState(title: "健康数据不可用", detail: "此设备无法读取 Apple 健康数据。", symbol: "moon.zzz.fill")
        } else if health.isLoading {
            ProgressView("正在读取睡眠记录")
        } else if health.sleepReadFailed {
            EmptyHealthState(title: "睡眠数据读取失败", detail: "请解锁设备后下拉刷新。", symbol: "exclamationmark.triangle")
        } else if !health.hasRequestedAccess && health.lastRefreshedAt == nil {
            EmptyHealthState(title: "连接 Apple 健康", detail: "连接后可查看最近一次睡眠的时长、分期和夜间体征。", symbol: "moon.zzz.fill")
            Button("请求健康访问") { Task { await health.connectAndRefresh() } }
                .buttonStyle(.borderedProminent)
        } else {
            EmptyHealthState(title: "暂无可读取的睡眠记录", detail: "最近 36 小时内未读取到睡眠分期。可在 Apple 健康中检查睡眠记录与共享权限。", symbol: "moon.zzz.fill")
        }
    }

    @ViewBuilder private var sleepHistorySection: some View {
        SectionHeadline(title: "近 7 日睡眠时长", subtitle: "按醒来日期归组，缺失不补算")
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                if health.sleepHistoryFailed {
                    EmptyHealthState(title: "读取 7 日睡眠失败", detail: "请解锁设备后下拉刷新。", symbol: "exclamationmark.triangle")
                } else if health.sleepHistory.allSatisfy({ !$0.hasRecord }) {
                    EmptyHealthState(title: "暂无 7 日睡眠记录", detail: "最近 7 天内未读取到睡眠分期。可在 Apple 健康中检查睡眠记录与共享权限。", symbol: "moon.zzz.fill")
                        .frame(minHeight: 160)
                } else {
                    Chart(health.sleepHistory) { day in
                        BarMark(x: .value("日期", day.date),
                                y: .value("睡眠分钟", day.asleepMinutes))
                            .foregroundStyle(day.hasRecord ? HealthTheme.sleep : HealthTheme.muted.opacity(0.25))
                    }
                    .frame(height: 180)
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 7)) {
                            AxisValueLabel(format: .dateTime.weekday(.abbreviated).locale(Locale(identifier: "zh_CN")))
                        }
                    }
                    .accessibilityLabel("近 7 日每日睡眠时长")
                    ForEach(health.sleepHistory) { day in
                        LabeledContent(ChineseDateTime.day(day.date),
                                       value: day.hasRecord ? "\(day.asleepMinutes / 60)小时\(day.asleepMinutes % 60)分" : "无记录")
                    }
                }
                Text("无记录的日子不代表当晚没睡，可能是未戴表、未授权或未记录；不跨缺失天数连线或补算。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }
        }
    }

    @ViewBuilder private var sleepRegularitySection: some View {
        SectionHeadline(title: "睡眠时间规律", subtitle: "近七个完整日 · 按醒来日期归组")
        HealthCard {
            VStack(alignment: .leading, spacing: 9) {
                if health.sleepRegularityFailed {
                    Text("读取睡眠规律失败，请解锁设备后下拉刷新。")
                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                } else if let result = health.sleepRegularity {
                    LabeledContent("有记录天数", value: "\(result.observedDays) / 7")
                    LabeledContent("可比较的相邻日", value: "\(result.adjacentPairs) 对")
                    if let onset = result.medianOnsetChange, let wake = result.medianWakeChange {
                        LabeledContent("入睡时刻变动中位数", value: "\(Int(onset.rounded())) 分钟")
                        LabeledContent("醒来时刻变动中位数", value: "\(Int(wake.rounded())) 分钟")
                    } else {
                        Text("至少需要两个相邻日期的睡眠记录。")
                            .font(.subheadline).foregroundStyle(HealthTheme.muted)
                    }
                    Text("以分期记录的首末睡眠样本估计入睡与醒来时刻；分段作息或记录缺失会影响结果。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                } else {
                    ProgressView("读取睡眠规律")
                }
            }
        }
    }
}

private struct NightReadingDetail: View {
    let metric: HealthMetric
    @EnvironmentObject private var health: HealthViewModel

    var body: some View {
        List {
            Section("本次睡眠 · 最近记录") {
                if let reading = health.nightReadings[metric.id] {
                    LabeledContent("测量值", value: "\(metric.display(reading.value)) \(reading.unit)")
                    LabeledContent("记录时间", value: reading.recordedAt.formatted(
                        .dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))
                    ))
                    LabeledContent("数据来源", value: reading.source)
                } else if health.failedNightMetricIDs.contains(metric.id) {
                    Text("本次读取失败，请返回睡眠页面并下拉刷新。")
                } else {
                    Text("本次睡眠期间暂无可读取的记录。")
                }
            }
            NavigationLink("查看全部时段的记录与趋势") {
                MetricDetailView(metric: metric)
            }
        }
        .navigationTitle(metric.name)
    }
}
