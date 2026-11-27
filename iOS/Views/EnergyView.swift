import SwiftUI
import HealthCore

/// 身体能量页：今日精力与疲劳自评（0–10 分，用户自己打分），以及近 7 日
/// 自评记录与三组描述性关联。分数是你自己的感受，不从 HRV 或任何生理
/// 信号推算；关联只是描述性相关，不是因果关系，也不是显著性检验。
struct EnergyView: View {
    @EnvironmentObject private var health: HealthViewModel
    @State private var energyToday: Double?
    @State private var fatigueToday: Double?
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
                    } else {
                        ProgressView("正在读取能量记录")
                    }
                    Text("本页分数只记录你自己的感受，不生成能量评分，不作疾病判断。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }.frame(maxWidth: .infinity, alignment: .leading).padding(18)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("身体能量")
            .task {
                energyToday = health.recoveryInputs.energy(on: Date())
                fatigueToday = health.recoveryInputs.fatigue(on: Date())
                if health.recoveryLoadedAt == nil { await health.loadRecovery() }
            }
            .refreshable {
                await health.loadRecovery()
                energyToday = health.recoveryInputs.energy(on: Date())
                fatigueToday = health.recoveryInputs.fatigue(on: Date())
            }
        }
        .accessibilityIdentifier("energy-screen")
    }

    private var ratingSection: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("今日自评").font(.headline)
                ratingRow(title: "精力", value: $energyToday, onChange: { value in
                    health.recoveryInputs.rateEnergy(on: Date(), value: value)
                    Task { await health.loadRecovery() }
                })
                ratingRow(title: "疲劳", value: $fatigueToday, onChange: { value in
                    health.recoveryInputs.rateFatigue(on: Date(), value: value)
                    Task { await health.loadRecovery() }
                })
                Text("0–10 分，分数越高表示那种感觉越强。精力与疲劳分开打分，互不推算；只保存今天最后一次打分。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }
        }
    }

    private func ratingRow(title: String, value: Binding<Double?>, onChange: @escaping (Double) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                Text(value.wrappedValue.map { "\(Int($0)) 分" } ?? "未记录")
                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(0...10, id: \.self) { score in
                    Button {
                        value.wrappedValue = Double(score)
                        onChange(Double(score))
                    } label: {
                        Text("\(score)")
                            .font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(value.wrappedValue == Double(score) ? HealthTheme.v3Energy : Color(.systemGray6))
                            .foregroundStyle(value.wrappedValue == Double(score) ? Color.white : Color.primary)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title)\(score)分")
                }
            }
        }
    }

    private func weekSection(_ journal: RecoveryJournal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "近 7 日自评", subtitle: "按日期归组，未记录的日子不补算")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    if journal.days.allSatisfy({ $0.energy == nil && $0.fatigue == nil }) {
                        EmptyHealthState(title: "近 7 天还没有自评记录", detail: "先在上方为今天打分，明天起这里会逐日积累。", symbol: "flame")
                            .frame(minHeight: 120)
                    } else {
                        ForEach(journal.days.reversed(), id: \.load.date) { day in
                            HStack {
                                Text(day.load.date.formatted(dayStyle)).font(.subheadline)
                                Spacer()
                                Text("精力 \(day.energy.map { "\(Int($0.value))" } ?? "—")\(changeText(day.energyChange))")
                                    .font(.subheadline)
                                Text("疲劳 \(day.fatigue.map { "\(Int($0.value))" } ?? "—")\(changeText(day.fatigueChange))")
                                    .font(.subheadline)
                            }
                            if day.load.date != journal.days.first?.load.date { Divider() }
                        }
                    }
                    Text("变化值是与前一天自评的差；前一天未记录时不显示变化。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func associationsSection(_ journal: RecoveryJournal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeadline(title: "关联观察", subtitle: "至少 7 对配对天数才显示")
            HealthCard {
                VStack(alignment: .leading, spacing: 9) {
                    associationRow(title: "睡眠时长与次日精力", association: journal.sleepAndLaterEnergy,
                                   positive: "睡眠时间越长，次日精力倾向于越高",
                                   negative: "睡眠时间越长，次日精力倾向于越低")
                    associationRow(title: "前日训练负荷与次日心率变异性（HRV）变化", association: journal.previousLoadAndSDNN,
                                   positive: "前日训练负荷越高，次日静息 HRV 相对基线的变化倾向于越大",
                                   negative: "前日训练负荷越高，次日静息 HRV 相对基线的变化倾向于越小")
                    associationRow(title: "睡眠时长与次日 HRV 变化", association: journal.sleepAndLaterSDNN,
                                   positive: "睡眠时间越长，次日静息 HRV 相对基线的变化倾向于越大",
                                   negative: "睡眠时间越长，次日静息 HRV 相对基线的变化倾向于越小")
                    Text("以上是描述性等级相关（斯皮尔曼相关系数），不是因果关系，也不是显著性检验；配对天数不足 7 天时不显示。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
        }
    }

    private func associationRow(title: String, association: RecoveryJournal.Association, positive: String, negative: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.subheadline.weight(.semibold))
                Spacer()
                if let rho = association.rho {
                    Text(String(format: "ρ %.2f · %d 对", rho, association.pairedDays))
                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                } else {
                    Text("配对 \(association.pairedDays) 天，不足 7 对")
                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                }
            }
            if let rho = association.rho {
                Text(rho > 0 ? positive : (rho < 0 ? negative : "两项之间未见单调关联倾向"))
                    .font(.subheadline).foregroundStyle(HealthTheme.muted)
            }
        }
    }

    private func changeText(_ change: Double?) -> String {
        guard let change else { return "" }
        if change > 0 { return "（+\(Int(change))）" }
        if change < 0 { return "（\(Int(change))）" }
        return "（不变）"
    }
}
