import SwiftUI
import HealthCore


/// 身体能量页：今日精力与疲劳自评（0–10 分，用户自己打分），以及近 7 日
/// 自评记录与三组描述性关联。分数是你自己的感受，不从 HRV 或任何生理
/// 信号推算；关联只是描述性相关，不是因果关系，也不是显著性检验。
struct EnergyView: View {
    @EnvironmentObject private var health: HealthViewModel
    @State private var energyToday: Double?
    @State private var fatigueToday: Double?
    @State private var showingClearAllConfirmation = false

    private let dayStyle = Date.FormatStyle.dateTime.month().day().weekday(.abbreviated).locale(Locale(identifier: "zh_CN"))


    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("精力与疲劳，是你自己的记录")
                        .font(.title2.bold()).foregroundStyle(HealthTheme.ink)
                    if health.recoveryFailed {
                        EmptyHealthState(title: "能量记录读取失败", detail: "请解锁设备后下拉刷新。", symbol: "exclamationmark.triangle")
                    } else if let journal = health.recoveryJournal {
                        ratingSection
                        weekSection(journal)
                        associationsSection(journal)
                        clearAllSection
                    } else {
                        ProgressView("正在读取能量记录")
                    }
                    Text("本页分数只记录你自己的感受，不生成能量评分，不作疾病判断；仅保存在本机，不进入备份。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("身体能量")
            .task { loadToday() }
            .onChange(of: health.recoveryInputs.saved) { _ in loadToday() }
            .refreshable { await health.loadRecovery() }
            .accessibilityIdentifier("EnergyScreen")
        }
    }


    private func loadToday() {
        energyToday = health.recoveryInputs.energy(on: Date())
        fatigueToday = health.recoveryInputs.fatigue(on: Date())
    }


    /// Build 28 P1-5: 删除自评入口。清空全部自评需二次确认；睡眠目标
    /// 与核实记录不是评分，不受影响。自评仅保存在本机，不进入备份。
    private var clearAllSection: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 9) {
                Text("删除自评").font(.headline)
                Text("清空全部自评会删除所有精力、疲劳与训练用力评分，且无法恢复。睡眠目标与核实记录不受影响。仅保存在本机，不进入备份。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
                Button("清空全部自评", role: .destructive) {
                    showingClearAllConfirmation = true
                }
                .font(.subheadline)
                .accessibilityLabel("清空全部自评")
                .disabled(!health.recoveryInputs.hasAnySelfRating)
            }
        }
        .confirmationDialog("清空全部自评？", isPresented: $showingClearAllConfirmation, titleVisibility: .visible) {
            Button("清空全部自评", role: .destructive) {
                health.recoveryInputs.clearAllSelfRatings()
                energyToday = nil
                fatigueToday = nil
                Task { await health.loadRecovery() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将删除所有精力、疲劳与训练用力评分，且无法恢复。")
        }
    }


    private var ratingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeadline(title: "今日自评", subtitle: "0–10 分，凭你此刻的感受")
            ratingRow(title: "精力", value: $energyToday, systemImage: "bolt.fill") { value in
                health.recoveryInputs.rateEnergy(on: Date(), value: value)
            }
            ratingRow(title: "疲劳", value: $fatigueToday, systemImage: "bed.double.fill") { value in
                health.recoveryInputs.rateFatigue(on: Date(), value: value)
            }
            if energyToday != nil || fatigueToday != nil {
                HStack(spacing: 12) {
                    if energyToday != nil {
                        Button("删除今日精力评分", role: .destructive) {
                            health.recoveryInputs.deleteEnergy(on: Date())
                            energyToday = nil
                            Task { await health.loadRecovery() }
                        }
                        .font(.subheadline)
                        .accessibilityLabel("删除今日精力评分")
                    }
                    if fatigueToday != nil {
                        Button("删除今日疲劳评分", role: .destructive) {
                            health.recoveryInputs.deleteFatigue(on: Date())
                            fatigueToday = nil
                            Task { await health.loadRecovery() }
                        }
                        .font(.subheadline)
                        .accessibilityLabel("删除今日疲劳评分")
                    }
                }
            }
            Text("精力与疲劳各是独立的一维自评。0 分代表完全没有该感受，10 分代表感受最强。")
                .font(.footnote).foregroundStyle(HealthTheme.muted)
        }
    }


    private func ratingRow(title: String, value: Binding<Double?>, systemImage: String, onRate: @escaping (Double) -> Void) -> some View {
        HealthCard {
            HStack {
                Label(title, systemImage: systemImage).font(.headline)
                Spacer()
                if let value = value.wrappedValue {
                    Text("\(Int(value)) 分")
                        .font(.headline)
                        .accessibilityLabel("\(title) \(Int(value)) 分")
                }
            }
            HStack(spacing: 7) {
                ForEach(0...10, id: \.self) { score in
                    let selected = value.wrappedValue == Double(score)
                    Button("\(score)") {
                        value.wrappedValue = Double(score)
                        onRate(Double(score))
                    }
                    .font(.subheadline.weight(selected ? .bold : .regular))
                    .frame(width: 30, height: 30)
                    .background(selected ? HealthTheme.ink : HealthTheme.surface)
                    .foregroundStyle(selected ? .white : HealthTheme.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .accessibilityLabel("\(title) \(score) 分")
                }
            }
            if value.wrappedValue == nil {
                Text("还没有为今天打分").font(.footnote).foregroundStyle(HealthTheme.muted)
            }
        }
    }


    private func weekSection(_ journal: RecoveryJournal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "近 7 日记录", subtitle: "只显示你已经打分的日子")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if journal.days.isEmpty {
                        EmptyHealthState(title: "暂无自评记录", detail: "为今天打分后，这里会显示近 7 日的精力与疲劳记录。", symbol: "bolt.fill")
                    } else {
                        ForEach(journal.days, id: \.load.date) { day in
                            HStack {
                                Text(day.load.date.formatted(dayStyle)).font(.subheadline)
                                Spacer()
                                Text("精力 \(day.energy.map { String(format: "%.0f", $0.value) } ?? "–")")
                                    .font(.subheadline)
                                Text("疲劳 \(day.fatigue.map { String(format: "%.0f", $0.value) } ?? "–")")
                                    .font(.subheadline)
                                if day.energy != nil || day.fatigue != nil {
                                    Button("删除当日自评") {
                                        health.recoveryInputs.deleteEnergy(on: day.load.date)
                                        health.recoveryInputs.deleteFatigue(on: day.load.date)
                                        if Calendar.current.isDateInToday(day.load.date) {
                                            energyToday = nil
                                            fatigueToday = nil
                                        }
                                        Task { await health.loadRecovery() }
                                    }
                                    .font(.subheadline)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("删除\(day.load.date.formatted(dayStyle))的自评")
                                }
                            }
                            if day.load.date != journal.days.last?.load.date { Divider() }
                        }
                    }
                }
            }
        }
    }


    private func associationsSection(_ journal: RecoveryJournal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "三组描述性关联", subtitle: "只看同期的高低趋势，不做因果判断")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    let samples = journal.days.filter { $0.energy != nil || $0.fatigue != nil }
                    if samples.count < 3 {
                        EmptyHealthState(title: "样本还太少", detail: "至少需要 3 天的自评记录，才会显示三组描述性关联。", symbol: "chart.bar")
                    } else {
                        associationRow(title: "睡眠时长 – 之后精力", text: associationText(journal.sleepAndLaterEnergy))
                        Divider()
                        associationRow(title: "前日训练负荷 – 次日心率变异性", text: associationText(journal.previousLoadAndSDNN))
                        Divider()
                        associationRow(title: "睡眠时长 – 之后心率变异性", text: associationText(journal.sleepAndLaterSDNN))
                    }
                }
            }
        }
    }


    private func associationText(_ association: RecoveryJournal.Association) -> String {
        if let rho = association.rho {
            return String(format: "相关系数 %.2f，配对 %d 天", rho, association.pairedDays)
        }
        return "配对 \(association.pairedDays) 天，不足 7 对"
    }


    private func associationRow(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.headline)
            Text(text).font(.subheadline)
        }
    }
}
