import SwiftUI
import Charts
import HealthCore

/// 自主恢复页：今日静息 HRV（SDNN）与静息心率相对 30 天个人基线的位置，
/// 以及日内各小时静息 HRV 分布。只描述相对位置，不生成恢复分数，
/// 不作压力或疲劳判断，不作疾病诊断。
struct AutonomicRecoveryView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    private let hourStyle = Date.FormatStyle.dateTime.hour().locale(Locale(identifier: "zh_CN"))
    private let timeStyle = Date.FormatStyle.dateTime.month().day().hour().minute().locale(Locale(identifier: "zh_CN"))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("心率变异性（HRV）与静息心率相对个人基线的位置")
                        .font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                    recoveryContent
                    Text("本页只描述与个人基线的相对位置，不生成恢复分数，不作疾病判断。出现胸痛、严重呼吸困难等症状，应立即寻求急救。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("恢复基线")
            .task {
                if health.recoveryLoadedAt == nil { await health.loadRecovery() }
            }
            .refreshable { await health.loadRecovery() }
        }
        .accessibilityIdentifier("autonomic-recovery-screen")
    }

    @ViewBuilder private var recoveryContent: some View {
        if health.autonomicFailed {
            EmptyHealthState(title: "恢复基线读取失败", detail: "请解锁设备后下拉刷新。", symbol: "exclamationmark.triangle")
        } else if let day = health.autonomicDay {
            patternCard(day)
            if let sdnn = day.dailySDNN {
                observationCard(title: "HRV（SDNN）", metricID: "hrv", observation: sdnn, unit: "毫秒")
            }
            if let bpm = day.dailyRestingBPM {
                observationCard(title: "静息心率", metricID: "restingHeartRate", observation: bpm, unit: "次/分")
            }
            if day.dailySDNN == nil && day.dailyRestingBPM == nil {
                EmptyHealthState(title: "暂无今日恢复基线数据", detail: "今天还没有可读取的静息 HRV 或静息心率记录。可在 Apple 健康中检查记录与共享权限。", symbol: "waveform.path.ecg")
            }
            hourlySection(day)
            sourceCard(day)
        } else {
            ProgressView("正在读取恢复基线")
        }
    }

    private func patternCard(_ day: AutonomicRecoveryDay) -> some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("今日两项指标的同向变化").font(.headline)
                Text(day.pattern.rawValue).font(.title3.bold()).foregroundStyle(HealthTheme.ink)
                Text("同向变化只是恢复观察的背景，不是经过验证的压力或疲劳量表；单项指标请看下面各自与基线的对比。")
                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
            }
        }
    }

    private func observationCard(title: String, metricID: String, observation: AutonomicRecoveryDay.Observation, unit: String) -> some View {
        let metric = HealthCatalog.byID[metricID]
        let valueText: String
        if let metric {
            valueText = "\(metric.display(observation.value)) \(unit)"
        } else {
            valueText = "\(observation.value) \(unit)"
        }
        return HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(observation.direction.rawValue)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(directionColor(observation.direction))
                }
                Text(valueText).font(.largeTitle.bold()).monospacedDigit()
                if let median = observation.baselineMedian {
                    LabeledContent("个人基线中位数", value: "\(Int(median.rounded())) \(unit)")
                }
                if let band = observation.baselineMiddleHalf {
                    LabeledContent("基线中间一半范围", value: "\(Int(band.lowerBound.rounded()))–\(Int(band.upperBound.rounded())) \(unit)")
                }
                LabeledContent("今日采样", value: "\(observation.sampleCount) 条")
                LabeledContent("基线参考天数", value: "\(observation.referenceDays) 天")
                LabeledContent("最近采样", value: observation.lastSample.formatted(timeStyle))
                if observation.baselineMedian == nil {
                    Text("基线参考天数不足 7 天时不计算基线位置，只显示今日中位数。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func hourlySection(_ day: AutonomicRecoveryDay) -> some View {
        let points = day.hours.compactMap { hour -> (start: Date, value: Double)? in
            guard let observation = hour.restingSDNN else { return nil }
            return (hour.start, observation.value)
        }
        return VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "日内静息 HRV 分布", subtitle: "各小时静息采样中位数 · 只显示有采样的小时")
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    if points.isEmpty {
                        EmptyHealthState(title: "今日暂无按小时的静息 HRV", detail: "今天还没有可读取的静息 HRV 采样。", symbol: "waveform.path.ecg")
                            .frame(minHeight: 140)
                    } else {
                        Chart {
                            ForEach(points, id: \.start) { point in
                                BarMark(x: .value("小时", point.start), y: .value("SDNN 毫秒", point.value))
                                    .foregroundStyle(HealthTheme.v3Recovery)
                            }
                            if let median = day.dailySDNN?.baselineMedian {
                                RuleMark(y: .value("基线中位数", median))
                                    .foregroundStyle(HealthTheme.v3Muted)
                                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                                    .annotation(position: .top, alignment: .trailing) {
                                        Text("基线 \(Int(median.rounded())) 毫秒").font(.caption).foregroundStyle(HealthTheme.v3Muted)
                                    }
                            }
                        }
                        .frame(height: 180)
                        .chartXAxis {
                            AxisMarks(values: .stride(by: .hour, count: 3)) {
                                AxisValueLabel(format: hourStyle)
                            }
                        }
                        .accessibilityLabel("今日各小时静息 HRV 分布")
                    }
                    Text("已采样 \(day.observedHours) 小时 · 共 \(day.hours.count) 个已过小时（\(Int((day.observedHourFraction * 100).rounded()))%。没有采样的小时留空，不补零。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func sourceCard(_ day: AutonomicRecoveryDay) -> some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("数据来源与口径").font(.headline)
                Text("来源：Apple 健康 SDNN 采样（静息场景）与静息心率记录；基线取近 30 天每日中位数，中间一半范围为基线分布的中间 50%。")
                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
                Text("静息心率只作为当日的背景，不会按小时分摊到 HRV 采样上。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
                if let diagnostics = health.rawSampleDiagnostics {
                    LabeledContent("样本来源", value: diagnostics.sources.isEmpty ? "未取到样本" : diagnostics.sources.joined(separator: "、"))
                    Text("取回 \(diagnostics.fetchedCount) 条 · 排除非手表 \(diagnostics.excludedNonWatchCount) 条 · 排除训练中 \(diagnostics.excludedDuringWorkoutCount) 条 · 去重丢弃 \(diagnostics.droppedDuplicateCount) 条 · 未来丢弃 \(diagnostics.droppedFutureCount) 条\(diagnostics.truncated ? " · 已截断" : "")")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func directionColor(_ direction: TrendDirection) -> Color {
        switch direction {
        case .stable: return HealthTheme.v3RecoveryText
        case .higher, .lower: return HealthTheme.v3EnergyText
        case .insufficient: return HealthTheme.v3Muted
        }
    }
}
