import SwiftUI
import HealthCore

struct RecordsView: View {
    @EnvironmentObject private var health: HealthViewModel
    @EnvironmentObject private var journal: JournalStore
    @State private var showingMeasurement = false
    @State private var showingJournal = false
    @State private var searchText = ""

    private func visibleMetrics(in group: MetricGroup) -> [HealthMetric] {
        HealthCatalog.all.filter { $0.group == group && (searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) || $0.id.localizedCaseInsensitiveContains(searchText)) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section("自己记录") {
                    Button { showingMeasurement = true } label: {
                        Label("录入血压、血糖或体重", systemImage: "plus.circle.fill")
                    }
                    Button { showingJournal = true } label: {
                        Label("添加症状、用药或健康笔记", systemImage: "square.and.pencil")
                    }
                }
                Section("专题") {
                    NavigationLink {
                        ActivityView()
                    } label: {
                        Label("运动与训练记录", systemImage: "figure.run")
                    }
                }
                ForEach(MetricGroup.allCases) { group in
                    if !visibleMetrics(in: group).isEmpty {
                    Section(group.rawValue) {
                        ForEach(visibleMetrics(in: group)) { metric in
                            NavigationLink { MetricDetailView(metric: metric) } label: {
                                HStack {
                                    Image(systemName: metric.symbol)
                                        .frame(width: 24)
                                        .foregroundStyle(HealthTheme.jade)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(metric.name)
                                        Text(health.readings[metric.id].map { "上次记录 · \(ChineseDateTime.full($0.recordedAt))" }
                                             ?? "暂无可读取记录")
                                            .font(.caption).foregroundStyle(HealthTheme.muted)
                                    }
                                    Spacer()
                                    Text(health.readings[metric.id].map { "\(metric.display($0.value)) \(metric.unitText)" } ?? "—")
                                        .font(.subheadline.monospacedDigit())
                                }
                            }
                        }
                    }
                    }
                }
                Section("个人健康日志") {
                    if journal.entries.isEmpty {
                        Text("暂无笔记").foregroundStyle(HealthTheme.muted)
                    }
                    ForEach(journal.entries) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack { Text(entry.category.rawValue).font(.caption).foregroundStyle(HealthTheme.muted)
                                Spacer()
                                Text(entry.timestamp, style: .date).font(.caption).foregroundStyle(HealthTheme.muted)
                            }
                            Text(entry.title).font(.headline)
                            if !entry.detail.isEmpty { Text(entry.detail).font(.subheadline) }
                        }.padding(.vertical, 4)
                    }.onDelete(perform: journal.remove)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("健康数据库")
            .searchable(text: $searchText, prompt: "搜索心率、HRV、血糖等")
            .refreshable { await health.refresh() }
            .sheet(isPresented: $showingMeasurement) { ManualMeasurementView() }
            .sheet(isPresented: $showingJournal) { JournalEntryView() }
            .alert("本地记录", isPresented: Binding(
                get: { journal.errorMessage != nil },
                set: { if !$0 { journal.errorMessage = nil } }
            )) { Button("好的", role: .cancel) { journal.errorMessage = nil } }
            message: { Text(journal.errorMessage ?? "") }
        }
    }
}

struct ManualMeasurementView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var kind = 0
    @State private var value1 = ""
    @State private var value2 = ""
    @State private var busy = false
    @State private var localError: String?
    private let labels = ["血压（mmHg）", "血糖（mg/dL）", "体重（kg）"]

    var body: some View {
        NavigationStack {
            Form {
                Picker("测量类型", selection: $kind) {
                    ForEach(labels.indices, id: \.self) { index in Text(labels[index]).tag(index) }
                }
                .pickerStyle(.segmented)
                TextField(kind == 0 ? "收缩压，例如 120" : (kind == 1 ? "血糖 mg/dL" : "体重 kg"), text: $value1)
                    .keyboardType(.decimalPad)
                if kind == 0 {
                    TextField("舒张压，例如 80", text: $value2).keyboardType(.decimalPad)
                }
                Text("仅写入你明确录入的测量数据；请按照真实测量结果填写，不要填估计值。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }
            .navigationTitle("录入健康测量")
            .alert("保存失败", isPresented: Binding(
                get: { localError != nil },
                set: { if !$0 { localError = nil } }
            )) { Button("好的", role: .cancel) { localError = nil } }
            message: { Text(localError ?? "") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let one = Double(value1) else { return }
                        busy = true
                        Task {
                            let saved: Bool
                            switch kind {
                            case 0:
                                saved = await health.savePressure(systolic: one, diastolic: Double(value2) ?? 0)
                            case 1: saved = await health.saveGlucose(one)
                            default: saved = await health.saveWeight(one)
                            }
                            busy = false
                            if saved { dismiss() }
                            else { localError = health.message ?? "写入失败，请检查 Apple 健康权限" }
                        }
                    }
                    .disabled(busy || Double(value1) == nil || (kind == 0 && Double(value2) == nil))
                }
            }
        }
    }
}

struct JournalEntryView: View {
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var category: JournalEntry.Category = .symptom
    @State private var title = ""
    @State private var detail = ""

    var body: some View {
        NavigationStack {
            Form {
                Picker("类别", selection: $category) {
                    ForEach(JournalEntry.Category.allCases, id: \.self) { value in
                        Text(value.rawValue).tag(value)
                    }
                }
                TextField("标题，例如：服药后轻微不适", text: $title)
                TextField("记录详情", text: $detail, axis: .vertical)
                    .lineLimit(3...8)
                Text("该笔记只保存在本机应用私有目录中。卸载 App 可能删除数据，请自行导出备份。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }
            .navigationTitle("新增健康记录")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { journal.add(category: category, title: title, detail: detail); dismiss() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
