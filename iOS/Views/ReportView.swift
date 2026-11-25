import SwiftUI
import HealthCore

struct ReportView: View {
    @EnvironmentObject private var health: HealthViewModel
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exportState: PrimaryButtonState = .idle
    @State private var period = ReportPeriod.week
    @State private var periodReport: PeriodHealthReport?
    @State private var retry = 0

    private struct LoadKey: Equatable {
        let period: ReportPeriod
        let refreshed: Date?
        let retry: Int
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HealthHero {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("PRIVATE HEALTH REPORT", systemImage: "lock.shield.fill")
                                .font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(.white.opacity(0.75))
                            Text("把每一次记录，变成更清晰的理解")
                                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                            Text("本机生成 · 不上传云端 · 数据可溯源")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 38)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    SectionHeadline(title: "时段报告", subtitle: "本机 Apple 健康 · 统计至本次读取时刻")
                    Picker("报告时段", selection: $period) {
                        Text("今日").tag(ReportPeriod.day)
                        Text("近 7 天").tag(ReportPeriod.week)
                        Text("近 30 天").tag(ReportPeriod.month)
                    }.pickerStyle(.segmented)
                    if let report = periodReport, report.period == period {
                        Text(report.rangeText).font(.footnote)
                        ForEach(report.rows) { row in
                            VStack(alignment: .leading, spacing: 4) {
                                LabeledContent(row.name, value: row.result)
                                Text(row.detail).font(.caption).foregroundStyle(.secondary)
                            }.accessibilityElement(children: .combine)
                        }
                        Text("缺失日期不计入汇总。今天仅统计至读取时刻。").font(.footnote)
                        Button("重新读取时段数据") { retry += 1 }
                    } else {
                        ProgressView("正在读取时段数据")
                    }
                    SectionHeadline(title: "最近记录观察", subtitle: "以下观察依据最近一次刷新，可包含所选时段之前的记录")
                    ForEach(health.insights) { insight in
                        HealthCard {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack(spacing: 9) {
                                    Image(systemName: "checkmark.seal.fill").foregroundStyle(HealthTheme.teal)
                                    Text(insight.title).font(.headline).foregroundStyle(HealthTheme.ink)
                                }
                                Text(insight.body).font(.subheadline).foregroundStyle(HealthTheme.muted)
                            }
                        }
                    }
                    if let refreshed = health.lastRefreshedAt {
                        Text("读取时间：\(refreshed.formatted())")
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                    }
                    HealthPrimaryButton(
                        title: exportState == .success ? "已生成 PDF" : "生成本地 PDF 健康摘要",
                        icon: "square.and.arrow.up",
                        state: exportState
                    ) {
                        do {
                            guard let report = periodReport, report.period == period else { return }
                            exportURL = try PDFReportExporter.export(periodReport: report, readings: health.readings,
                                                                     sleep: health.sleep,
                                                                     insights: health.insights,
                                                                     failedMetricIDs: health.failedMetricIDs)
                            exportState = .success
                        } catch {
                            exportError = error.localizedDescription
                            exportState = .failure
                        }
                    }
                    .disabled(periodReport?.period != period)
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("分享本次 PDF 报告", systemImage: "doc.richtext")
                                .frame(maxWidth: .infinity)
                        }.buttonStyle(.bordered).controlSize(.large)
                    }
                    HealthCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("分析可信度说明", systemImage: "info.circle.fill")
                                .font(.headline).foregroundStyle(HealthTheme.ink)
                            Text("当前版本为离线规则解读，不调用远程 AI。没有数据时不输出健康分数或疾病风险结论。后续 AI 接入必须独立授权并提供完整数据处理说明。")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                    }
                }.padding(18)
            }
            .task(id: LoadKey(period: period, refreshed: health.lastRefreshedAt, retry: retry)) {
                periodReport = nil
                exportURL = nil
                exportState = .idle
                do {
                    let report = try await PeriodHealthReport.read(period: period, repository: HealthKitRepository())
                    try Task.checkCancellation()
                    periodReport = report
                } catch { /* A new selection or navigation cancels the old report. */ }
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("健康报告")
            .alert("导出失败", isPresented: Binding(
                get: { exportError != nil },
                set: { if !$0 { exportError = nil } }
            )) { Button("好的", role: .cancel) { exportError = nil } }
            message: { Text(exportError ?? "") }
        }
    }
}
