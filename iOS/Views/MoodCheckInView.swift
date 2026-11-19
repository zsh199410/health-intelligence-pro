import SwiftUI

/// Drop-in Today card. A mood is always a person's own check-in; this card
/// never claims to infer emotion from sensors or from the stress estimate.
struct MoodCheckInCard: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @StateObject private var mood = MoodStore()
    @State private var activeSheet: MoodSheet?
    @State private var showHealthManagement = false

    private enum MoodSheet: Identifiable {
        case new
        case history

        var id: String {
            switch self {
            case .new: return "new"
            case .history: return "history"
            }
        }
    }

    var body: some View {
        HealthCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "face.smiling")
                        .font(.title3.weight(.medium))
                        .foregroundStyle(HealthTheme.v4Accent)
                        .frame(width: 42, height: 42)
                        .background(HealthTheme.v4Accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 14))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("此刻心情")
                            .font(.headline)
                            .foregroundStyle(HealthTheme.v4Ink)
                        Text("由你主动记录，不由身体数据推断")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v4Muted)
                    }
                    Spacer(minLength: 0)
                }

                if mood.isLoading && !mood.hasLoaded {
                    ProgressView("读取最近记录…")
                        .font(.subheadline)
                } else if let latest = mood.latest {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(latest.feeling)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(HealthTheme.v4Ink)
                        if !latest.labels.isEmpty {
                            Text(latest.labels.joined(separator: " · "))
                                .font(.subheadline)
                                .foregroundStyle(HealthTheme.v4Muted)
                        }
                        if !latest.associations.isEmpty {
                            Text("相关因素：\(latest.associations.joined(separator: " · "))")
                                .font(.caption)
                                .foregroundStyle(HealthTheme.v4Muted)
                        }
                        Text("最近记录：\(ChineseDateTime.full(latest.recordedAt)) · \(latest.source)")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v4Muted)
                            .fixedSize(horizontal: false, vertical: true)
                        if latest.origin == .appleHealth && mood.latestNeedsVerification {
                            Text("已提交到 Apple 健康，当前无法核对该记录；请在健康 App 中查看。")
                                .font(.caption)
                                .foregroundStyle(HealthTheme.v4Muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .accessibilityElement(children: .combine)
                } else {
                    Text("暂无可读取的此刻心情记录")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.v4Muted)
                    Text("可以现在记录，也可以选择读取 Apple 健康中的心境记录。")
                        .font(.caption)
                        .foregroundStyle(HealthTheme.v4Muted)
                }

                if let error = mood.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(HealthTheme.v4Muted)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel("心情记录提示：\(error)")
                }

                Button {
                    activeSheet = .new
                } label: {
                    Label("记录此刻心情", systemImage: "plus")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.v4Accent)
                .accessibilityIdentifier("mood.checkIn")

                if !mood.localRecords.isEmpty {
                    Button("管理本机记录（\(mood.localRecords.count)）") { activeSheet = .history }
                        .font(.caption.weight(.medium))
                }
                if mood.latest?.origin == .appleHealth {
                    Button("修改或删除 Apple 健康记录") { showHealthManagement = true }
                        .font(.caption.weight(.medium))
                }
                Button("读取 Apple 健康心境记录") {
                    Task { await mood.connectHealthHistory() }
                }
                .font(.caption.weight(.medium))
            }
        }
        .task(id: onboardingComplete) {
            guard onboardingComplete else { return }
            await mood.refresh()
            if !Task.isCancelled { mood.startObserving() }
        }
        .onDisappear { mood.stopObserving() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && onboardingComplete { Task { await mood.refresh() } }
        }
        .sheet(item: $activeSheet) { destination in
            switch destination {
            case .new:
                MoodCheckInView(store: mood)
            case .history:
                MoodLocalHistoryView(store: mood)
            }
        }
        .alert("在 Apple 健康管理记录", isPresented: $showHealthManagement) {
            Button("知道了", role: .cancel) {}
        } message: {
            Text("请打开 Apple 健康，前往“心理健康”中的“心境”查看、修改或删除原记录。此处不会覆盖原始心境样本。")
        }
    }
}

struct MoodCheckInView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MoodStore

    private let editing: LocalMoodRecord?
    @State private var feeling: MoodFeeling?
    @State private var selectedLabels: Set<MoodLabel>
    @State private var selectedAssociations: Set<MoodAssociation>
    @State private var destination: Destination
    @State private var attemptedSave = false

    private enum Destination: String, CaseIterable, Identifiable {
        case appleHealth, local
        var id: Self { self }
        var title: String { self == .appleHealth ? "Apple 健康" : "仅本机" }
    }

    init(store: MoodStore, editing: LocalMoodRecord? = nil) {
        self.store = store
        self.editing = editing
        _feeling = State(initialValue: editing?.feeling)
        _selectedLabels = State(initialValue: Set(editing?.labels ?? []))
        _selectedAssociations = State(initialValue: Set(editing?.associations ?? []))
        _destination = State(initialValue: editing == nil ? .appleHealth : .local)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 25) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(editing == nil ? "你现在感觉如何？" : "修改这次心情记录")
                            .font(.title2.weight(.bold))
                            .foregroundStyle(HealthTheme.v4Ink)
                        Text("这是你的主观感受，身体指标不会替你选择。")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v4Muted)
                    }

                    section(title: "选择此刻的感受", detail: "必选") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 126), spacing: 10)], spacing: 10) {
                            ForEach(MoodFeeling.allCases) { choice in
                                Button {
                                    feeling = choice
                                } label: {
                                    Label(choice.title, systemImage: choice.symbol)
                                        .font(.subheadline.weight(.medium))
                                        .frame(maxWidth: .infinity, minHeight: 52)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                .buttonStyle(MoodChoiceStyle(selected: feeling == choice))
                                .accessibilityAddTraits(feeling == choice ? .isSelected : [])
                            }
                        }
                    }

                    section(title: "哪些词更贴近你的感受？", detail: "可多选") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 10)], spacing: 10) {
                            ForEach(MoodLabel.allCases) { label in
                                Button(label.title) {
                                    if selectedLabels.contains(label) {
                                        selectedLabels.remove(label)
                                    } else {
                                        selectedLabels.insert(label)
                                    }
                                }
                                    .buttonStyle(MoodChoiceStyle(selected: selectedLabels.contains(label)))
                                    .accessibilityAddTraits(selectedLabels.contains(label) ? .isSelected : [])
                            }
                        }
                    }

                    section(title: "可能与什么有关？", detail: "可多选，可不填") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 102), spacing: 10)], spacing: 10) {
                            ForEach(MoodAssociation.allCases) { association in
                                Button(association.title) {
                                    if selectedAssociations.contains(association) {
                                        selectedAssociations.remove(association)
                                    } else {
                                        selectedAssociations.insert(association)
                                    }
                                }
                                    .buttonStyle(MoodChoiceStyle(selected: selectedAssociations.contains(association)))
                                    .accessibilityAddTraits(selectedAssociations.contains(association) ? .isSelected : [])
                            }
                        }
                    }

                    if editing == nil {
                        section(title: "保存位置", detail: nil) {
                            VStack(spacing: 10) {
                                ForEach(Destination.allCases) { option in
                                    Button(option.title) { destination = option }
                                        .buttonStyle(MoodChoiceStyle(selected: destination == option))
                                        .accessibilityAddTraits(destination == option ? .isSelected : [])
                                }
                            }
                            Text(destination == .appleHealth
                                 ? "保存时才请求 Apple 健康的心境写入权限。若失败，你可以改选仅本机，已选内容会保留。"
                                 : "仅保存在这台设备的受保护文件中，不写入 Apple 健康。")
                                .font(.caption)
                                .foregroundStyle(HealthTheme.v4Muted)
                        }
                    } else {
                        Text("仅修改这条本机记录，保留原记录时间；不会改写 Apple 健康历史。")
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v4Muted)
                    }

                    if attemptedSave, let error = store.errorMessage {
                        Label(error, systemImage: "exclamationmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(HealthTheme.v4Ink)
                            .fixedSize(horizontal: false, vertical: true)
                        if editing == nil && destination == .appleHealth {
                            Button("改为仅本机保存") {
                                destination = .local
                                attemptedSave = false
                            }
                            .font(.subheadline.weight(.semibold))
                        }
                    }
                }
                .padding(20)
            }
            .background(HealthTheme.v4Canvas.ignoresSafeArea())
            .navigationTitle(editing == nil ? "心情打卡" : "修改心情记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("取消") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    Task { await save() }
                } label: {
                    if store.isSaving {
                        ProgressView().tint(.white)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    } else {
                        Text(editing == nil ? "保存这次心情" : "保存修改")
                            .font(.headline)
                            .frame(maxWidth: .infinity, minHeight: 48)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(HealthTheme.v4Accent)
                .disabled(feeling == nil || store.isSaving)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(HealthTheme.v4Canvas)
            }
        }
    }

    private func section<Content: View>(
        title: String, detail: String?, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.headline).foregroundStyle(HealthTheme.v4Ink)
                if let detail {
                    Text(detail).font(.caption).foregroundStyle(HealthTheme.v4Muted)
                }
            }
            content()
        }
    }

    private func save() async {
        guard let feeling else { return }
        attemptedSave = true
        let success: Bool
        if let editing {
            success = store.saveLocally(
                feeling: feeling, labels: selectedLabels,
                associations: selectedAssociations, replacing: editing.id
            )
        } else if destination == .local {
            success = store.saveLocally(
                feeling: feeling, labels: selectedLabels, associations: selectedAssociations
            )
        } else {
            success = await store.save(
                feeling: feeling, labels: selectedLabels, associations: selectedAssociations
            )
        }
        if success { dismiss() }
    }
}

/// Local records can be edited or deleted here. Apple Health entries stay in
/// Apple's own record manager so this app never silently rewrites history.
private struct MoodLocalHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: MoodStore
    @State private var editing: LocalMoodRecord?
    @State private var pendingDelete: LocalMoodRecord?
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    Text("这些记录仅保存在本机。修改会保留原记录时间，删除不会影响 Apple 健康。")
                        .font(.subheadline)
                        .foregroundStyle(HealthTheme.v4Muted)
                        .padding(.bottom, 4)

                    ForEach(store.localRecords.sorted { $0.recordedAt > $1.recordedAt }) { record in
                        HealthCard {
                            VStack(alignment: .leading, spacing: 9) {
                                Text(record.feeling.title)
                                    .font(.headline)
                                    .foregroundStyle(HealthTheme.v4Ink)
                                Text(ChineseDateTime.full(record.recordedAt))
                                    .font(.caption)
                                    .foregroundStyle(HealthTheme.v4Muted)
                                if !record.labels.isEmpty {
                                    Text(record.labels.map(\.title).joined(separator: " · "))
                                        .font(.caption)
                                        .foregroundStyle(HealthTheme.v4Muted)
                                }
                                if !record.associations.isEmpty {
                                    Text("相关因素：\(record.associations.map(\.title).joined(separator: " · "))")
                                        .font(.caption)
                                        .foregroundStyle(HealthTheme.v4Muted)
                                }
                                HStack(spacing: 20) {
                                    Button("修改") { editing = record }
                                    Button("删除", role: .destructive) {
                                        pendingDelete = record
                                        showDeleteConfirmation = true
                                    }
                                }
                                .font(.subheadline.weight(.medium))
                                .padding(.top, 3)
                            }
                        }
                    }
                    if let error = store.errorMessage {
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(HealthTheme.v4Muted)
                    }
                }
                .padding(20)
            }
            .background(HealthTheme.v4Canvas.ignoresSafeArea())
            .navigationTitle("本机心情记录")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("完成") { dismiss() }
                }
            }
            .sheet(item: $editing) { record in
                MoodCheckInView(store: store, editing: record)
            }
            .confirmationDialog(
                "删除这条本机心情记录？",
                isPresented: $showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                if let pendingDelete {
                    Button("删除记录", role: .destructive) {
                        store.deleteLocal(id: pendingDelete.id)
                        self.pendingDelete = nil
                    }
                }
            } message: {
                Text("删除后不能撤销，Apple 健康中的记录不会改变。")
            }
        }
    }
}

private struct MoodChoiceStyle: ButtonStyle {
    let selected: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? HealthTheme.v4Accent : HealthTheme.v4Ink)
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(
                selected ? HealthTheme.v4Accent.opacity(0.12) : HealthTheme.v4Card,
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? HealthTheme.v4Accent : HealthTheme.v4Line, lineWidth: 1)
            }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
