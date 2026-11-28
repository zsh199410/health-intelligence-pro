import SwiftUI
import Charts
import HealthCore

/// 训练负荷页：近 7 日训练负荷（活动分钟 × 主观用力程度），训练记录
/// （含 RPE 评分入口）与最近一次训练的 48 小时运动后回顾。
/// 负荷只在训练有真实 RPE 评分时才算；未评分的训练不计入负荷。
struct TrainingLoadView: View {
    @EnvironmentObject private var health: HealthViewModel
    private let dayStyle = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))
    private let timeStyle = Date.FormatStyle.dateTime.hour().minute().locale(Locale(identifier: "zh_CN"))

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("训练负荷来自真实训练与你的主观用力评分")
                        .font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                    if health.recoveryFailed {
                        EmptyHealthState(title: "训练记录读取失败", detail: "请解锁设备后下拉刷新。", symbol: "exclamationmark.triangle")
                    } else if let report = health.recoveryReport {
                        loadSection(report)
                        workoutsSection(report)
                        followUpSection
                    } else {
                        ProgressView("正在读取训练记录")
                    }
                    Text("本页不推断你是否适合训练，也不给恢复倒计时；48 小时回顾只是观察记录。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("运动负荷")
            .task {
                if health.recoveryLoadedAt == nil { await health.loadRecovery() }
            }
            .refreshable { await health.loadRecovery() }
        }
        .accessibilityIdentifier("training-load-screen")
    }

    private func loadSection(_ report: RecoveryLoadReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "近 7 日训练负荷", subtitle: "活动分钟 × 主观用力程度（0–10）")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if report.days.allSatisfy({ $0.trainingLoad == nil }) {
                        EmptyHealthState(title: "近 7 天还没有可计的训练负荷", detail: "有训练但未评分的日子不计入负荷；先在下方为训练打分。", symbol: "figure.run")
                            .frame(minHeight: 120)
                    } else {
                        Chart(report.days, id: \.date) { day in
                            if let load = day.trainingLoad {
                                BarMark(
                                    x: .value("日期", day.date, unit: .day),
                                    y: .value("负荷", load)
                                )
                                .foregroundStyle(HealthTheme.v3Load)
                            }
                        }
                        .frame(height: 120)
                        .chartXAxis { AxisMarks(values: .stride(by: .day)) { AxisValueLabel(format: .dateTime.day()) } }
                    }
                    ForEach(report.days.reversed(), id: \.date) { day in
                        trainingLoadDayRow(day, report: report)
                        if day.date != report.days.first?.date { Divider() }
                    }
                    trainingLoadTotals(report)
                    Text("未核实、未评分或记录冲突的日子负荷未知，在图中留空，不按 0 算；只有你确认当天未运动的日子才计 0。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func trainingLoadDayRow(_ day: RecoveryLoadReport.Day, report: RecoveryLoadReport) -> some View {
        let verified = health.recoveryInputs.isActivityVerified(on: day.date)
        let hasWorkout = day.latestWorkoutEnd != nil
        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(day.date.formatted(dayStyle))
                Spacer()
                Text(trainingDayText(day, report: report))
            }
            .font(.subheadline)
            HStack(spacing: 8) {
                Text(verified ? "已核实" : "未核实")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(verified ? HealthTheme.ink : HealthTheme.muted)
                    .accessibilityLabel(verified ? "训练负荷已核实" : "训练负荷未核实")
                Spacer()
                if verified {
                    Button("取消核实") {
                        health.recoveryInputs.unverifyActivity(on: day.date)
                        Task { await health.loadRecovery() }
                    }
                    .font(.caption)
                    .accessibilityLabel("取消核实\(day.date.formatted(dayStyle))的训练负荷")
                } else if hasWorkout {
                    Button("确认数据完整") {
                        health.recoveryInputs.verifyActivity(on: day.date)
                        Task { await health.loadRecovery() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("确认\(day.date.formatted(dayStyle))的训练数据完整")
                } else {
                    Button("确认当天未运动") {
                        health.recoveryInputs.verifyActivity(on: day.date)
                        Task { await health.loadRecovery() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                    .accessibilityLabel("确认\(day.date.formatted(dayStyle))当天未运动")
                }
            }
        }
    }

    private func trainingDayText(_ day: RecoveryLoadReport.Day, report: RecoveryLoadReport) -> String {
        if let load = day.trainingLoad {
            return load == 0 ? "已确认休息日，负荷 0" : "负荷 \(Int(load))"
        }
        if health.recoveryInputs.isActivityVerified(on: day.date) {
            if hasUnratedWorkout(on: day.date, report: report) {
                return "已核实，有训练未评分，负荷未知"
            }
            return "已核实，负荷未知"
        }
        return day.latestWorkoutEnd == nil ? "无训练记录，未核实" : "有训练，未核实"
    }

    private func hasUnratedWorkout(on date: Date, report: RecoveryLoadReport) -> Bool {
        let start = report.calendar.startOfDay(for: date)
        return health.recoveryWorkouts.contains { workout in
            report.calendar.startOfDay(for: workout.end) == start && workout.exertion == nil
        }
    }

    @ViewBuilder private func trainingLoadTotals(_ report: RecoveryLoadReport) -> some View {
        let loads = report.days.compactMap(\.trainingLoad)
        if let total = report.totalTrainingLoad {
            Text("本周累计负荷 \(Int(total))（7 天均已核实）")
                .font(.subheadline.weight(.semibold))
        } else if !loads.isEmpty {
            Text("局部总和（\(loads.count)/7 天有值）：\(Int(loads.reduce(0, +)))")
                .font(.subheadline.weight(.semibold))
            Text("有 \(report.days.filter { $0.trainingLoad == nil }.count) 天负荷未知，无法汇总本周完整总和。")
                .font(.subheadline).foregroundStyle(HealthTheme.muted)
        } else {
            Text("有 \(report.days.filter { $0.trainingLoad == nil }.count) 天负荷未知，无法汇总本周累计。")
                .font(.subheadline).foregroundStyle(HealthTheme.muted)
        }
    }

    private func workoutsSection(_ report: RecoveryLoadReport) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "训练记录", subtitle: "按已同步记录，未记录不代表没运动")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if health.recoveryWorkouts.isEmpty {
                        EmptyHealthState(title: "近 7 天没有训练记录", detail: "按已同步记录；手表或手机未同步的训练不会出现在这里。", symbol: "figure.run")
                            .frame(minHeight: 120)
                    } else {
                        ForEach(health.recoveryWorkouts.sorted(by: { $0.start > $1.start }), id: \.id) { workout in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Text(health.recoveryWorkoutTypeNames[workout.id] ?? "训练")
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(workout.start.formatted(dayStyle) + " " + workout.start.formatted(timeStyle))
                                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                                }
                                HStack {
                                    Text("活动 \(Int(workout.activeMinutes)) 分钟")
                                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                                    Spacer()
                                    Menu {
                                        Picker("主观用力程度", selection: exertionBinding(for: workout)) {
                                            ForEach(0...10, id: \.self) { score in
                                                Text("\(score) 分").tag(Double(score))
                                            }
                                        }
                                        if workout.exertion != nil {
                                            Button("清除评分", role: .destructive) {
                                                health.recoveryInputs.rateWorkout(id: workout.id, exertion: nil)
                                                Task { await health.loadRecovery() }
                                            }
                                        }
                                    } label: {
                                        Text(workout.exertion.map { "用力 \(Int($0)) 分" } ?? "未评分，点此打分")
                                            .font(.subheadline)
                                            .foregroundStyle(workout.exertion == nil ? HealthTheme.muted : HealthTheme.v3LoadText)
                                    }
                                }
                            }
                            if workout.id != health.recoveryWorkouts.sorted(by: { $0.start > $1.start }).last?.id { Divider() }
                        }
                    }
                    Text("主观用力程度（RPE）0–10 分由你本人打分：0 是毫不费力，10 是竭尽全力；没有评分的训练不计入负荷。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func exertionBinding(for workout: RatedWorkout) -> Binding<Double> {
        Binding(
            get: { workout.exertion ?? 5 },
            set: { value in
                health.recoveryInputs.rateWorkout(id: workout.id, exertion: value)
                Task { await health.loadRecovery() }
            }
        )
    }

    private var followUpSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "最近一次训练的 48 小时回顾", subtitle: "只观察已同步的记录，不作恢复判断")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if let followUp = health.recoveryFollowUps.sorted(by: { $0.workoutEndedAt > $1.workoutEndedAt }).first {
                        let name = health.recoveryWorkoutTypeNames[followUp.workoutID] ?? "训练"
                        Text("\(name) · \(followUp.workoutEndedAt.formatted(dayStyle)) \(followUp.workoutEndedAt.formatted(timeStyle)) 结束")
                            .font(.subheadline.weight(.semibold))
                        Text("回顾窗口至 \(followUp.windowEnd.formatted(dayStyle)) \(followUp.windowEnd.formatted(timeStyle))（48 小时，或下一次训练开始前）")
                            .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        Text("窗口内静息心率变异性（HRV）小时数：\(followUp.restingSDNNHours.count) 小时")
                            .font(.subheadline)
                        Text("窗口内精力自评 \(followUp.energyRatings.count) 次，疲劳自评 \(followUp.fatigueRatings.count) 次")
                            .font(.subheadline)
                        if followUp.energyRatings.isEmpty && followUp.fatigueRatings.isEmpty {
                            Text("窗口内还没有精力或疲劳自评；去身体能量页打分后会显示在这里。")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                    } else {
                        EmptyHealthState(title: "暂无可回顾的训练", detail: "需要一次有明确结束时间、且 48 小时内未被另一次训练打断的训练。", symbol: "clock")
                            .frame(minHeight: 120)
                    }
                    Text("本节不推断你是否适合训练，也不给恢复倒计时；窗口内有记录就显示，没有就不显示。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }
}
