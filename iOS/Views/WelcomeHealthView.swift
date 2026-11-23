import SwiftUI

/// Explicit informed onboarding: no HealthKit query or network transmission is
/// initiated by the welcome screen before the user requests it.
struct WelcomeHealthView: View {
    @EnvironmentObject private var health: HealthViewModel
    @Environment(\.dismiss) private var dismiss
    @AppStorage("onboardingComplete") private var onboardingComplete = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "heart.text.clipboard.fill")
                        .font(.system(size: 52, weight: .light))
                        .foregroundStyle(.white)
                        .frame(width: 94, height: 94)
                        .background(LinearGradient(colors: [HealthTheme.jade, HealthTheme.teal],
                                                   startPoint: .topLeading, endPoint: .bottomTrailing),
                                    in: RoundedRectangle(cornerRadius: 27))
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 7) {
                        Text("HEALTH INTELLIGENCE PRO")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .tracking(2).foregroundStyle(HealthTheme.teal)
                        Text("读懂健康，从真实数据开始")
                            .font(.system(.largeTitle, design: .rounded, weight: .bold))
                            .foregroundStyle(HealthTheme.ink)
                        Text("专为 iPhone 与 Apple Watch 设计的私人健康中枢。所有内容以你授权的健康记录为依据。")
                            .foregroundStyle(HealthTheme.muted)
                    }
                    welcomeRow("心脏与生命体征", "心率、HRV、ECG 历史、血氧、血压记录", "heart.fill", HealthTheme.coral)
                    welcomeRow("睡眠与恢复", "睡眠分期、夜间呼吸、腕温和个人基线", "moon.stars.fill", HealthTheme.indigo)
                    welcomeRow("隐私优先", "默认本机计算，不上传医疗资料；随时在系统健康中管理权限", "lock.shield.fill", HealthTheme.teal)
                    HealthCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("授权说明").font(.headline).foregroundStyle(HealthTheme.ink)
                            Text("接下来将弹出 Apple 健康的权限选择。你可以按项目选择；即使拒绝也可以使用本地健康日志。读取失败或没有记录时，不生成模拟数据或健康结论。")
                                .font(.subheadline).foregroundStyle(HealthTheme.muted)
                        }
                    }
                    HealthPrimaryButton(
                        title: health.isLoading ? "正在请求授权" : "连接 Apple 健康",
                        icon: "heart.text.square.fill",
                        state: health.isLoading ? .loading : .idle,
                        disabled: !health.isHealthAvailable
                    ) {
                        Task {
                            await health.connectAndRefresh()
                            // Do not mark onboarding complete if HealthKit authorization
                            // threw. Keep the explanation and retry/skip controls visible.
                            // A completed authorization request does not prove read access.
                            if health.hasRequestedAccess {
                                complete()
                            }
                        }
                    }
                    .accessibilityHint("打开苹果健康访问授权弹窗")
                    Button("先体验记录功能") { complete() }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(HealthTheme.jade)
                }
                .padding(22)
            }
            .background(HealthTheme.canvas.ignoresSafeArea())
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("跳过") { complete() } } }
        }
    }

    private func complete() { onboardingComplete = true; dismiss() }

    private func welcomeRow(_ title: String, _ description: String, _ symbol: String, _ tint: Color) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: symbol).font(.title2).foregroundStyle(tint)
                .frame(width: 52, height: 52)
                .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(HealthTheme.ink)
                Text(description).font(.subheadline).foregroundStyle(HealthTheme.muted)
            }
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }
}
