import SwiftUI
import Charts
import HealthCore

struct SleepView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .body) private var plotHeight = 148.0
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
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("睡眠健康")
            .refreshable { await health.refresh() }
        }
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
