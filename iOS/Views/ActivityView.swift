import SwiftUI
import HealthCore

struct ActivityView: View {
    @EnvironmentObject private var health: HealthViewModel
    @State private var workouts: [WorkoutRecord] = []
    @State private var readError = false
    private let repository = HealthKitRepository()
    private let metricIDs = ["stepCount", "activeEnergy", "vo2Max", "heartRateRecoveryOneMinute"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("运动与体能")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(HealthTheme.ink)
                Text("记录、来源和时间一起查看")
                    .font(.subheadline)
                    .foregroundStyle(HealthTheme.muted)
                if health.failedMetricIDs.contains(where: { metricIDs.contains($0) }) {
                    V3ErrorBanner(failedCount: health.failedMetricIDs.filter { metricIDs.contains($0) }.count)
                }
                SectionHeadline(title: "近期指标")
                ForEach(metricIDs, id: \.self) { id in
                    if let metric = HealthCatalog.byID[id] {
                        NavigationLink {
                            MetricDetailView(metric: metric)
                        } label: {
                            MetricTile(metric: metric, reading: health.readings[id])
                        }
                        .buttonStyle(.plain)
                    }
                }
                SectionHeadline(title: "训练记录", subtitle: "来自 Apple 健康的已保存训练")
                if readError {
                    HealthCard { Text("训练记录读取失败，请下拉刷新重试。") }
                } else if workouts.isEmpty {
                    HealthCard {
                        EmptyHealthState(title: "暂无训练记录", detail: "记录训练后，这里会显示时间、时长和来源。", symbol: "figure.walk")
                    }
                } else {
                    HealthCard {
                        VStack(spacing: 12) {
                            ForEach(workouts) { workout in
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(workout.name).font(.headline)
                                    Text("\(ChineseDateTime.full(workout.start)) · \(Int(workout.end.timeIntervalSince(workout.start) / 60)) 分钟")
                                    Text("来源：\(workout.source)")
                                }
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                if workout.id != workouts.last?.id { Divider() }
                            }
                        }
                    }
                }
                Text("运动负荷需要完整的训练时长、强度和个人基线；数据不足时不生成负荷分数。")
                    .font(.footnote)
                    .foregroundStyle(HealthTheme.muted)
            }
            .padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle("运动与体能")
        .refreshable { await health.refresh(); await load() }
        .task { await load() }
    }

    private func load() async {
        do {
            workouts = try await repository.recentWorkouts()
            readError = false
        } catch {
            workouts = []
            readError = true
        }
    }
}
