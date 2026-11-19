import SwiftUI
import Charts
import HealthCore

struct HeartView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let metricIDs = ["restingHeartRate", "hrv", "walkingHeartRateAverage",
                             "systolic", "diastolic", "atrialFibrillationBurden", "heartRateRecoveryOneMinute", "vo2Max"]
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        Image(systemName: "heart.fill").font(.title)
                            .foregroundStyle(HealthTheme.coral)
                            .frame(width: 58, height: 58)
                            .background(HealthTheme.coral.opacity(0.1), in: RoundedRectangle(cornerRadius: 18))
                        VStack(alignment: .leading, spacing: 6) {
                            Text("心脏健康").font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                            Text("理解变化，不由单次数值推断疾病")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                    }
                    if let metric = HealthCatalog.byID["heartRate"] {
                        NavigationLink { MetricDetailView(metric: metric) } label: {
                            LatestHeartRateCard(
                                reading: health.readings["heartRate"],
                                readFailed: health.failedMetricIDs.contains("heartRate"),
                                accessRequested: health.hasRequestedAccess,
                                lastCheckedAt: health.lastCheckedAtByMetric["heartRate"]
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("heart-latest-reading")
                    }
                    SectionHeadline(title: "其他心血管指标", subtitle: "每项显示测量时间与来源；点击查看历史")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(metricIDs, id: \.self) { id in
                            if let metric = HealthCatalog.byID[id] {
                                NavigationLink { MetricDetailView(metric: metric) } label: {
                                    MetricTile(metric: metric, reading: health.readings[id])
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    SectionHeadline(title: "心电图 ECG", subtitle: "来自苹果系统的已完成测量")
                    if health.ecgs.isEmpty {
                        HealthCard {
                            EmptyHealthState(title: "暂无 ECG 历史记录",
                                             detail: "请使用手表系统 ECG App 进行测量。功能可能受设备、年龄、地区与授权限制。")
                        }
                    } else {
                        ForEach(health.ecgs) { ecg in
                            NavigationLink { ECGDetailView(ecg: ecg) } label: {
                                HealthCard {
                                    HStack(spacing: 12) {
                                        Image(systemName: "waveform.path.ecg")
                                            .foregroundStyle(HealthTheme.coral).font(.title3)
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(ecg.classification).font(.headline).foregroundStyle(HealthTheme.ink)
                                            Text(ChineseDateTime.full(ecg.recordedAt))
                                                .font(.caption).foregroundStyle(HealthTheme.muted)
                                            if let rate = ecg.averageHeartRate {
                                                Text("平均心率 \(Int(rate.rounded())) 次/分")
                                                    .font(.caption).foregroundStyle(HealthTheme.muted)
                                            }
                                        }
                                        Spacer()
                                        Image(systemName: "chevron.right").foregroundStyle(HealthTheme.muted)
                                    }
                                }
                            }.buttonStyle(.plain)
                        }
                    }
                    SectionHeadline(title: "系统心率提醒", subtitle: "苹果系统已产生的通知记录")
                    if health.heartEvents.isEmpty {
                        HealthCard { EmptyHealthState(title: "没有可读取的通知记录",
                                                     detail: "可能尚未发生通知、未授权，或设备/地区不支持。", symbol: "bell.slash") }
                    } else {
                        HealthCard {
                            VStack(spacing: 14) {
                                ForEach(health.heartEvents) { event in
                                    HStack(spacing: 12) {
                                        Image(systemName: "bell.badge.fill").foregroundStyle(HealthTheme.amber)
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(event.type).font(.subheadline.weight(.medium))
                                            Text(ChineseDateTime.full(event.date)).font(.caption).foregroundStyle(HealthTheme.muted)
                                        }
                                        Spacer()
                                    }
                                    if event.id != health.heartEvents.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    Text("本页显示已保存的健康记录。无法自行启动苹果系统 ECG 采集，也不对 ECG 进行疾病诊断。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }.padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("心脏")
            .refreshable { await health.refresh() }
        }
    }
}

struct ECGDetailView: View {
    let ecg: ECGSummary
    @EnvironmentObject private var health: HealthViewModel
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HealthPill(title: "只读记录", icon: "lock.fill", tint: HealthTheme.coral)
                        Text(ecg.classification).font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                        Text(ChineseDateTime.full(ecg.recordedAt)).font(.caption).foregroundStyle(HealthTheme.muted)
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ECG 波形").font(.headline).foregroundStyle(HealthTheme.ink)
                        if health.isECGLoading {
                            ProgressView("读取心电信号…").frame(maxWidth: .infinity, minHeight: 170)
                        } else if let points = health.ecgVoltages[ecg.id], !points.isEmpty {
                            // The waveform is visual only; its meaning (the
                            // classification and recording time above) is
                            // already text, so VoiceOver skips the chart.
                            Chart(points) { point in
                                LineMark(x: .value("时间 / 秒", point.seconds),
                                         y: .value("电压 / mV", point.millivolts))
                                    .lineStyle(StrokeStyle(lineWidth: 1.1))
                                    .foregroundStyle(HealthTheme.coral)
                            }.frame(height: 230).accessibilityHidden(true)
                            Text("信号已抽样用于图表显示，非医学级校准导出。")
                                .font(.caption2).foregroundStyle(HealthTheme.muted)
                        } else {
                            EmptyHealthState(title: "没有可读取的波形", detail: "检查 HealthKit ECG 读取授权和原始数据可用性。")
                        }
                    }
                }
                Text("心电波形仅来自 Apple Watch 已完成的 ECG；本应用不能发起新检测。任何异常应由有资质的医疗专业人员结合症状判断。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }.padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle("ECG 详情")
        .task(id: ecg.id) { await health.loadECGVoltage(for: ecg.id) }
    }
}

struct MetricDetailView: View {
    let metric: HealthMetric
    @EnvironmentObject private var health: HealthViewModel
    @State private var selectedDays = 30
    private let ranges = [7, 30, 90]

    private var points: [TrendPoint] { health.trends[metric.id] ?? [] }
    private var baseline: BaselineSummary {
        BaselineAnalyzer.summarize(points: points, now: .now)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MetricTile(metric: metric, reading: health.readings[metric.id])
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack {
                            Text("历史趋势").font(.headline).foregroundStyle(HealthTheme.ink)
                            Spacer()
                            Picker("日期范围", selection: $selectedDays) {
                                ForEach(ranges, id: \.self) { days in Text("\(days)天").tag(days) }
                            }
                            .pickerStyle(.menu)
                            .accessibilityLabel("选择历史趋势范围")
                        }
                        if points.isEmpty {
                            EmptyHealthState(title: "暂无趋势记录", detail: "检查数据来源和 Apple 健康授权。", symbol: "chart.xyaxis.line")
                                .frame(minHeight: 180)
                        } else {
                            Chart(points) { point in
                                LineMark(x: .value("日期", point.recordedAt),
                                         y: .value(metric.name, point.value))
                                    .interpolationMethod(.linear)
                                    .foregroundStyle(HealthTheme.teal)
                                PointMark(x: .value("日期", point.recordedAt),
                                          y: .value(metric.name, point.value))
                                    .symbolSize(13).foregroundStyle(HealthTheme.jade)
                            }.frame(height: 225)
                                .chartXAxis { AxisMarks(values: .automatic(desiredCount: 4)) }
                                .accessibilityLabel("\(metric.name) 近\(selectedDays)天每日汇总趋势图")
                        }
                        Text("按自然日汇总可用记录；最新读数与每日平均值可能不同。不同测量来源不一定可直接比较。")
                            .font(.footnote).foregroundStyle(HealthTheme.muted)
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 11) {
                        HStack(spacing: 9) {
                            Image(systemName: "chart.line.uptrend.xyaxis")
                                .foregroundStyle(HealthTheme.teal)
                            Text("个人趋势观察").font(.headline).foregroundStyle(HealthTheme.ink)
                        }
                        Text(baseline.direction.rawValue)
                            .font(.title3.bold()).foregroundStyle(HealthTheme.ink)
                        if let reference = baseline.baseline, let change = baseline.percentageChange {
                            Text(String(format: "此前 %d 个不同日期的每日汇总基线约为 %.1f %@，最近变化 %+.1f%%。", baseline.uniqueDays, reference, metric.unitText, change * 100))
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        } else {
                            Text("至少需要 7 个不同日期的历史记录才能计算个人趋势。缺少历史数据时不生成健康评分。")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                        Text("趋势采用本地统计方法，仅用于健康观察，不是医学参考范围或疾病预警阈值。")
                            .font(.caption2).foregroundStyle(HealthTheme.muted)
                    }
                }
                if let reading = health.readings[metric.id] {
                    HealthCard {
                        VStack(spacing: 12) {
                            LabeledContent("记录来源", value: reading.source)
                            LabeledContent("记录时间", value: ChineseDateTime.full(reading.recordedAt))
                            LabeledContent("数据新鲜度", value: FreshnessEvaluator.evaluate(recordedAt: reading.recordedAt, now: .now, acceptableAge: 24 * 3600).rawValue)
                            LabeledContent("单位", value: metric.unitText.isEmpty ? "无量纲" : metric.unitText)
                        }
                    }
                }
                Text("未授权、系统未测量、或所在地区不支持，均可能造成无数据。请勿据此推断身体正常。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }.padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle(metric.name)
        .task(id: selectedDays) { await health.loadTrend(for: metric, days: selectedDays) }
    }
}
