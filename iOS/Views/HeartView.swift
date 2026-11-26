import SwiftUI
import Charts
import HealthCore

struct HeartView: View {
    @EnvironmentObject private var health: HealthViewModel
    private let metricIDs = ["heartRate", "restingHeartRate", "hrv", "walkingHeartRateAverage",
                             "systolic", "diastolic", "atrialFibrillationBurden", "heartRateRecoveryOneMinute", "vo2Max"]
    private let columns = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
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
                    NavigationLink {
                        ECGCenterView()
                    } label: {
                        HealthCard {
                            HStack {
                                Label("心电中心", systemImage: "waveform.path.ecg")
                                    .font(.headline)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(HealthTheme.muted)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("ecg-center-entry")
                    SectionHeadline(title: "心血管指标", subtitle: "可点击任意指标查看来源与历史")
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(metricIDs, id: \.self) { id in
                            if let metric = HealthCatalog.byID[id] {
                                NavigationLink { MetricDetailView(metric: metric) } label: {
                                    MetricTile(metric: metric, reading: health.readings[id])
                                }.buttonStyle(.plain)
                            }
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
                                            Text(event.date.formatted()).font(.caption).foregroundStyle(HealthTheme.muted)
                                        }
                                        Spacer()
                                    }
                                    if event.id != health.heartEvents.last?.id { Divider() }
                                }
                            }
                        }
                    }
                    Text("本页仅展示授权的历史记录。无法自行启动苹果系统 ECG 采集，也不对 ECG 进行疾病诊断。")
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
    @State private var trace: ECGWaveform?
    @State private var loading = true
    @State private var readFailed = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HealthPill(title: "只读记录", icon: "lock.fill", tint: HealthTheme.coral)
                        LabeledContent("记录来源", value: ecg.source ?? "未提供")
                        Text(ecg.classification).font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                        Text(ecg.recordedAt.formatted(.dateTime.year().month().day().hour().minute().second().locale(Locale(identifier: "zh_CN"))))
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                        if let seconds = ecg.duration {
                            LabeledContent("记录时长", value: "\(seconds.formatted(.number.precision(.fractionLength(1)))) 秒")
                        }
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("ECG 波形").font(.headline).foregroundStyle(HealthTheme.ink)
                        if loading {
                            ProgressView("读取心电信号…").frame(maxWidth: .infinity, minHeight: 170)
                        } else if readFailed {
                            EmptyHealthState(title: "读取 ECG 波形失败", detail: "请检查健康访问或记录的采样时间，再打开此记录。")
                        } else if let trace {
                            ECGTracePlot(trace: trace)
                        } else {
                            EmptyHealthState(title: "没有可读取的波形", detail: "检查 HealthKit ECG 读取授权和原始数据可用性。")
                        }
                    }
                }
                if let trace {
                    let report = ecg.report(trace: trace, timeZone: .current)
                    DisclosureGroup("本地心电记录摘要") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(report).textSelection(.enabled)
                            ShareLink(item: report) { Label("分享文字摘要", systemImage: "square.and.arrow.up") }
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                Text("心电波形来自 Apple 健康中已保存的 ECG 记录；本应用不能发起新检测。任何异常应由有资质的医疗专业人员结合症状判断。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }.padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle("ECG 详情")
        .task(id: ecg.id) {
            loading = true
            trace = nil
            readFailed = false
            do {
                let result = try await health.ecgWaveform(for: ecg.id)
                guard !Task.isCancelled else { return }
                trace = result
            } catch {
                guard !Task.isCancelled else { return }
                readFailed = true
            }
            loading = false
        }
    }
}

private struct ECGTracePlot: View {
    let trace: ECGWaveform
    @State private var enlarged = false
    @State private var offset: Double = 0

    var body: some View {
        let first = trace.samples.first?.seconds ?? 0
        let last = trace.samples.last?.seconds ?? first
        let duration = last - first
        let zoom = enlarged && duration > 5
        let start = first + min(offset, max(0, duration - 5))
        let visible = zoom ? trace.segments(in: start...(start + 5)) : trace.segments
        if duration > 5 {
            Toggle("展开 5 秒波形", isOn: $enlarged)
            if zoom {
                Slider(value: $offset, in: 0...(duration - 5))
                    .accessibilityLabel("波形起始秒数")
                Text("显示 \(start, specifier: "%.1f") 至 \(start + 5, specifier: "%.1f") 秒")
                    .font(.caption)
            }
        }
        if visible.isEmpty {
            Text("此范围缺少可绘制的连续波形。")
        } else {
            Chart {
                ForEach(visible) { segment in
                    ForEach(segment.points) { point in
                        if segment.points.count == 1 {
                            PointMark(x: .value("时间 / 秒", point.seconds),
                                      y: .value("电压 / mV", point.millivolts))
                        } else {
                            LineMark(x: .value("时间 / 秒", point.seconds),
                                     y: .value("电压 / mV", point.millivolts),
                                     series: .value("连续片段", segment.id))
                        }
                    }
                }
            }
            .chartXScale(domain: zoom ? start...(start + 5) : first...max(last, first + 0.001))
            .foregroundStyle(HealthTheme.coral)
            .frame(height: 230).accessibilityHidden(true)
        }
        Text("原始采样 \(trace.samples.count) 点 · 时间间断 \(trace.gapCount) 处")
            .font(.caption).foregroundStyle(HealthTheme.muted)
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
                            LabeledContent("记录时间", value: reading.recordedAt.formatted())
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
