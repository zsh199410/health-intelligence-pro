import SwiftUI
import HealthCore

/// In-app update center (Build 26, P0). Test-fixture flow only in this
/// build: the manifest, the install page and the artifact are test data.
/// Version check, release notes, download status, SHA-256 integrity
/// check, and system share to LCsign. The app never installs, re-signs,
/// or bypasses iOS signing; installation is always done by the user in
/// their own trusted flow (LCsign / TestFlight).
struct UpdateCenterView: View {
    @StateObject private var store = UpdateCenterStore()
    private let dateStyle = Date.FormatStyle.dateTime.year().month().day().hour().minute()
        .locale(Locale(identifier: "zh_CN"))

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HealthCard {
                    VStack(alignment: .leading, spacing: 10) {
                        HealthPill(title: "测试清单 · 非正式发布", icon: "testtube.2", tint: HealthTheme.amber)
                        Text("当前更新中心使用测试数据验证流程：清单、安装包均为测试内容，不连接正式更新服务器，不提供真实安装包。")
                            .font(.subheadline).foregroundStyle(HealthTheme.muted)
                    }
                }
                HealthCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("当前版本").font(.headline).foregroundStyle(HealthTheme.ink)
                        Text("\(store.installedVersion)（Build \(store.installedBuild)）")
                            .font(.title3.bold()).foregroundStyle(HealthTheme.ink)
                        Text("版本与 Build 取自本应用安装包。")
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                    }
                }
                HealthPrimaryButton(
                    title: store.isChecking ? "正在检查…" : "检查更新",
                    state: store.isChecking ? .loading : .idle,
                    disabled: store.isChecking
                ) {
                    store.checkUsingTestFixture()
                }
                .accessibilityIdentifier("update-center-check-button")
                checkStateSection
                updateCard
                Text("本应用不静默安装、不绕过 iOS 签名、不自动重签名。安装始终由你在 LCsign 或 TestFlight 等受信任流程中自行完成。")
                    .font(.footnote).foregroundStyle(HealthTheme.muted)
            }.padding(18)
        }
        .background(HealthTheme.canvas.ignoresSafeArea())
        .navigationTitle("检查更新")
    }

    @ViewBuilder
    private var checkStateSection: some View {
        switch store.checkState {
        case .idle:
            Text("点按「检查更新」，使用测试清单验证更新流程。")
                .font(.subheadline).foregroundStyle(HealthTheme.muted)
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                Text("正在检查更新…").font(.subheadline).foregroundStyle(HealthTheme.muted)
            }
        case .upToDate(let manifest):
            HealthCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("已是最新版").font(.headline).foregroundStyle(HealthTheme.ink)
                    Text("清单版本 \(manifest.version)（Build \(manifest.build)），与当前安装一致。")
                        .font(.subheadline).foregroundStyle(HealthTheme.muted)
                }
            }
        case .updateAvailable:
            EmptyView()
        case .failed(let message):
            HealthCard {
                VStack(alignment: .leading, spacing: 10) {
                    Label("检查未完成", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(HealthTheme.coral)
                    Text(message).font(.subheadline).foregroundStyle(HealthTheme.muted)
                    Button("重试") { store.checkUsingTestFixture() }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    @ViewBuilder
    private var updateCard: some View {
        if case .updateAvailable(let manifest) = store.checkState {
            HealthCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("有新版本").font(.headline).foregroundStyle(HealthTheme.ink)
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text("\(manifest.version)（Build \(manifest.build)）")
                            .font(.title3.bold()).foregroundStyle(HealthTheme.ink)
                    }
                    LabeledContent("发布渠道", value: manifest.channel == "managed-ipa" ? "自签安装包（受控渠道）" : "TestFlight")
                    LabeledContent("发布日期", value: manifest.publishedAt.formatted(dateStyle))
                    if store.isTestFixture {
                        Text("测试清单：安装页为保留测试地址，不可作为真实更新来源。")
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                    }
                    Text("更新说明").font(.headline).foregroundStyle(HealthTheme.ink)
                    ForEach(manifest.releaseNotes, id: \.self) { note in
                        Text("• \(note)").font(.subheadline).foregroundStyle(HealthTheme.ink)
                    }
                    downloadSection(manifest: manifest)
                }
            }
        }
    }

    @ViewBuilder
    private func downloadSection(manifest: HealthUpdateManifest) -> some View {
        if store.isTestFixture {
            switch store.downloadState {
            case .idle:
                Button("下载并校验安装包（测试）") {
                    store.downloadAndVerifyTestArtifact()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("update-center-download-button")
            case .downloading(let progress):
                VStack(alignment: .leading, spacing: 8) {
                    if let progress {
                        ProgressView(value: progress)
                    } else {
                        ProgressView()
                    }
                    Text("正在下载测试安装包…").font(.subheadline).foregroundStyle(HealthTheme.muted)
                }
            case .verifying:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在校验完整性…").font(.subheadline).foregroundStyle(HealthTheme.muted)
                }
            case .verified(let url):
                VStack(alignment: .leading, spacing: 10) {
                    Label("完整性校验通过", systemImage: "checkmark.shield.fill")
                        .font(.headline).foregroundStyle(HealthTheme.teal)
                    if let digest = manifest.artifactSHA256 {
                        Text("SHA-256：\(String(digest.prefix(16)))…")
                            .font(.caption).foregroundStyle(HealthTheme.muted)
                            .textSelection(.enabled)
                    }
                    ShareLink(item: url) {
                        Label("分享至 LCsign", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.borderedProminent)
                    Text("测试文件不是真实安装包，不要安装。分享后请在 LCsign 中自行处理；本应用不执行安装。")
                        .font(.caption).foregroundStyle(HealthTheme.muted)
                }
            case .failed(let message):
                VStack(alignment: .leading, spacing: 10) {
                    Label("下载或校验失败", systemImage: "exclamationmark.triangle.fill")
                        .font(.headline).foregroundStyle(HealthTheme.coral)
                    Text(message).font(.subheadline).foregroundStyle(HealthTheme.muted)
                    Button("重新下载") { store.downloadAndVerifyTestArtifact() }
                        .buttonStyle(.bordered)
                }
            }
        } else {
            Link("前往更新", destination: manifest.installPageURL)
                .buttonStyle(.borderedProminent)
            Text("点按后在系统浏览器或 TestFlight 中打开更新页；实际安装由该渠道完成。")
                .font(.caption).foregroundStyle(HealthTheme.muted)
        }
    }
}
