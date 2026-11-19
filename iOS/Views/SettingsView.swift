import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var health: HealthViewModel
    @EnvironmentObject private var journal: JournalStore
    @Environment(\.dismiss) private var dismiss
    @AppStorage("themePreference") private var themePreference: AppThemePreference = .system
    @State private var showDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(HealthTheme.teal).font(.title2)
                            .frame(width: 48, height: 48)
                            .background(HealthTheme.teal.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
                        VStack(alignment: .leading, spacing: 4) {
                            Text("你的健康数据，由你控制").font(.headline)
                            Text("默认本机处理；不含广告跟踪或云端上传。")
                                .font(.caption).foregroundStyle(HealthTheme.muted)
                        }
                    }.padding(.vertical, 5)
                }
                Section("外观") {
                    Picker("主题", selection: $themePreference) {
                        ForEach(AppThemePreference.allCases) { pref in
                            Text(pref.title).tag(pref)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("跟随系统会随 iPhone 的浅色/深色设置自动切换；切换主题不会重新加载数据或丢失当前页面。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
                Section("Apple 健康") {
                    LabeledContent("当前设备支持", value: health.isHealthAvailable ? "是" : "否")
                    LabeledContent("已发起授权流程", value: health.hasRequestedAccess ? "是" : "否")
                    Button("授权或调整健康访问") { Task { await health.connectAndRefresh() } }
                        .disabled(health.isLoading || !health.isHealthAvailable)
                    Button("重新读取健康记录") { Task { await health.refresh() } }
                        .disabled(health.isLoading)
                    Text("出于隐私保护，HealthKit 不允许第三方 App 精确判断读取权限是否被拒绝；没有记录不等于测量正常。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
                Section("我的健康档案") {
                    LabeledContent("健康日志", value: "\(journal.entries.count) 条")
                    Button("清空 App 内全部健康日志", role: .destructive) { showDeleteConfirmation = true }
                        .disabled(journal.entries.isEmpty)
                    Text("清理只影响本应用私有日志，不会删除 Apple 健康中的测量数据。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
                Section("隐私与安全") {
                    Label("健康指标按需访问，不连接第三方服务器", systemImage: "network.slash")
                    Label("日志写入 App 私有目录并启用文件保护", systemImage: "iphone.gen3.radiowaves.left.and.right")
                    Label("PDF 仅在主动生成后交由系统分享", systemImage: "square.and.arrow.up")
                    Text("手表版采用独立 HealthKit 授权；从手表向手机只传递刷新时间，不传输原始医疗读数。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
                Section("Apple Watch 配套安装") {
                    Text("必须为 watchOS Target 提供正确的 Bundle ID、手表 UDID 和描述文件。你现有的第三方 P12 不保证包含 Watch 安装权限。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
                Section("关于") {
                    LabeledContent("产品", value: "健康中枢 Pro")
                    LabeledContent("版本", value: "1.0.0 · 工程候选版")
                    LabeledContent("健康数据", value: "HealthKit")
                    Text("非医疗器械，不用于疾病诊断或急救监护。")
                        .font(.footnote).foregroundStyle(HealthTheme.muted)
                }
            }
            .scrollContentBackground(.hidden)
            .background(HealthTheme.canvas.ignoresSafeArea())
            .navigationTitle("设置与隐私")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .confirmationDialog("确定清空本机日志？", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("永久清空本机健康日志", role: .destructive) { journal.removeAll() }
            } message: {
                Text("此操作不可撤销，不影响 Apple 健康的数据。")
            }
        }
    }
}
