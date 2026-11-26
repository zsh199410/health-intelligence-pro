import SwiftUI
import Charts
import HealthCore

/// Observational dashboard. Uses existing, recorded HealthKit measurements.
/// No composite recovery score or implied diagnosis is generated.
struct CardiovascularRecoveryView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var selectedDays = 30

    private let metricIDs = CardiovascularRecoveryCoverage.metricIDs
    private let ranges = [7, 30, 90]

    private var recovery: MetricReading? {
        CardiovascularRecoveryCoverage.oneMinuteRecovery(in: health.readings)
    }

    private var availableIDs: [String] {
        CardiovascularRecoveryCoverage.availableMetricIDs(in: health.readings)
    }

    private var trend: [TrendPoint] {
        let startOfToday = Calendar.current.startOfDay(for: .now)
        let start = Calendar.current.date(byAdding: .day, value: -(selectedDays - 1), to: startOfToday) ?? .distantPast
        return (health.trends["heartRateRecoveryOneMinute"] ?? [])
            .filter { $0.recordedAt >= start && $0.value.isFinite }
            .sorted { $0.recordedAt < $1.recordedAt }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 12) {
                        HealthPill(title: "历史实测 · 非诊断", icon: "heart.text.clipboard.fill", tint: HealthTheme.coral)
                        Text("运动后一分钟心率恢复")
                            .font(.headline).foregroundStyle(HealthTheme.ink)
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            if let recovery, let metric = HealthCatalog.byID["heartRateRecoveryOneMinute"] {
                                Text(metric.display(recovery.value))
                                    .font(.system(.largeTitle, design: .rounded, weight: .bold))
                                    .foregroundStyle(HealthTheme.ink)
                                Text(metric.unitText)
                                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
                            } else {
                                Text("—")
                                    .font(.largeTitle.bold()).foregroundStyle(HealthTheme.ink)
                                Text("暂无可用记录")
                                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
                            }
                        }
                        if let recovery {
                            LabeledContent("测量时间", value: ChineseDateTime.full(recovery.recordedAt))
                            LabeledContent("原始来源", value: recovery.source)
                        } else {
                            Text("没有记录不等于恢复能力差；可能未测量、未授权或设备不支持。")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                        Text("此数值反映一次已记录的运动后心率变化，不等于 HRV 或 VO₂max，也不能独立判断心脏疾病。")
                            .font(.footnote).foregroundStyle(HealthTheme.muted)
                    }
                }
                SectionHeadline(title: "历史变化", subtitle: "按自然日汇总，不把旧记录当作实时数据")
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Picker("查看时间范围", selection: $selectedDays) {
                            ForEach(ranges, id: \.self) { days in
                                Text("\(days) 天").tag(days)
                            }
                        }
                        .pickerStyle(.segmented)
                        .accessibilityLabel("心率恢复趋势时间范围")
                        if trend.isEmpty {
                            EmptyHealthState(title: "暂无可显示的趋势",
                                             detail: "可能没有本时段记录，也可能读取失败、未授权或设备不支持；请在 Apple 健康核查。",
                                             symbol: "chart.xyaxis.line")
                                .frame(minHeight: 160)
                        } else {
                            Chart(trend) { point in
                                LineMark(x: .value("日期", point.recordedAt),
                                         y: .value("一分钟心率恢复", point.value))
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(HealthTheme.coral)
                                PointMark(x: .value("日期", point.recordedAt),
                                          y: .value("一分钟心率恢复", point.value))
                                    .foregroundStyle(HealthTheme.coral)
                            }
                            .frame(height: 212)
                            .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                            .accessibilityLabel("心率恢复每日汇总趋势，过去 \\(selectedDays) 天")
                            Text("最近的趋势记录")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(HealthTheme.ink)
                            ForEach(trend.suffix(5)) { point in
                                LabeledContent(ChineseDateTime.full(point.recordedAt),
                                               value: String(format: "%.1f 次/分", point.value))
                            }
                        }
                        Text("不同运动强度、结束后静止状态及设备来源会影响可比性；图表仅用于观察变化。")
                            .font(.footnote).foregroundStyle(HealthTheme.muted)
                    }
                }
                SectionHeadline(title: "互补指标", subtitle: "指标各自独立，不能简单相加为一个恢复分数")
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(metricIDs.filter { $0 != "heartRateRecoveryOneMinute" }, id: \.self) { id in
                        if let metric = HealthCatalog.byID[id] {
                            NavigationLink {
                                MetricDetailView(metric: metric)
                            } label: {
                                MetricTile(metric: metric, reading: health.readings[id])
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 9) {
                        Label("数据覆盖", systemImage: "checkmark.shield")
                            .font(.headline).foregroundStyle(HealthTheme.ink)
                        Text("\(availableIDs.count) / \(metricIDs.count) 项指标有记录")
                            .font(.subheadline.weight(.medium)).foregroundStyle(HealthTheme.ink)
                        Text("覆盖数量只表示数据是否存在，不代表身体状况优劣。数据时间和来源请逐项查看。")
                            .font(.footnote).foregroundStyle(HealthTheme.muted)
                    }
                }
                Text("本页面不是医疗诊断、风险预测或临床运动试验。出现胸痛、呼吸困难、晕厥等症状时，不应依赖本页面数值排除疾病。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }
            .padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle("心血管恢复")
        .task(id: selectedDays) {
            if let metric = HealthCatalog.byID["heartRateRecoveryOneMinute"] {
                await health.loadTrend(for: metric, days: selectedDays)
            }
        }
        .accessibilityIdentifier("cardiovascular-recovery-screen")
    }
}
