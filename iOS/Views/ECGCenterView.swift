import HealthCore
import SwiftUI

struct ECGCenterView: View {
    @EnvironmentObject private var health: HealthViewModel

    var body: some View {
        List {
            if !health.isHealthAvailable {
                EmptyHealthState(title: "设备无法读取 ECG", detail: "请在支持 Apple 健康的 iPhone 上查看。")
            } else if health.isLoading && health.ecgs.isEmpty {
                ProgressView("读取心电记录…")
            } else if health.ecgReadFailed {
                EmptyHealthState(title: "心电记录读取失败", detail: "请解锁 iPhone 后下拉刷新。")
            } else if health.ecgs.isEmpty {
                EmptyHealthState(title: "暂无可读取的 ECG", detail: "最近 90 天内未读取到记录。可在 Apple 健康中检查记录和共享权限。")
            } else {
                let counts = Dictionary(grouping: health.ecgs, by: \.classification).mapValues(\.count)
                Section {
                    ForEach(counts.keys.sorted(), id: \.self) { label in
                        LabeledContent(label, value: "\(counts[label, default: 0]) 条")
                    }
                } header: {
                    Text("Apple 系统分类 · 共 \(health.ecgs.count) 条")
                } footer: {
                    Text("统计最近 90 个本地自然日内可读取的记录。每次心电图测量计一条。")
                }
                Section("历史记录") {
                    ForEach(health.ecgs.sorted { $0.recordedAt > $1.recordedAt }) { record in
                        NavigationLink {
                            ECGDetailView(ecg: record)
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(record.classification).font(.headline)
                                Text(record.recordedAt.formatted(.dateTime.year().month().day().hour().minute().locale(Locale(identifier: "zh_CN"))))
                                if let source = record.source {
                                    Text(source).font(.footnote).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("心电中心")
        .refreshable { await health.refresh() }
        .task {
            if health.lastRefreshedAt == nil && !health.isLoading {
                await health.refresh()
            }
        }
    }
}
