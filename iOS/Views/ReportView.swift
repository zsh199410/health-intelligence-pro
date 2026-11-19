import SwiftUI
import HealthCore

struct ReportView: View {
    @EnvironmentObject private var health: HealthViewModel
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var exportState: PrimaryButtonState = .idle
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    HealthHero {
                        VStack(alignment: .leading, spacing: 14) {
                            Label("私人健康报告", systemImage: "lock.shield.fill")
                                .font(.caption2.weight(.bold)).tracking(1.3).foregroundStyle(.white.opacity(0.75))
                            Text("把每一次记录，变成更清晰的理解")
                                .font(.system(.title2, design: .rounded, weight: .bold)).foregroundStyle(.white)
                            Text("本机生成 · 不上传云端 · 数据可溯源")
                                .font(.subheadline).foregroundStyle(.white.opacity(0.8))
                            Image(systemName: "doc.text.magnifyingglass")
                                .font(.system(size: 38)).foregroundStyle(.white.opacity(0.8))
                        }
                    }
                    SectionHeadline(title: "本次健康观察", subtitle: "使用已读取数据的可解释规则")
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
                        Text("读取时间：\(ChineseDateTime.full(refreshed))")
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                    }
                    HealthPrimaryButton(
                        title: exportState == .success ? "已生成 PDF" : "生成本地 PDF 健康摘要",
                        icon: "square.and.arrow.up",
                        state: exportState
                    ) {
                        do {
                            exportURL = try PDFReportExporter.export(readings: health.readings,
                                                                     sleep: health.sleep,
                                                                     insights: health.insights,
                                                                     failedMetricIDs: health.failedMetricIDs)
                            exportState = .success
                        } catch {
                            exportError = error.localizedDescription
                            exportState = .failure
                        }
                    }
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
