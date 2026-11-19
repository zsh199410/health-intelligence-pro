import SwiftUI
import HealthCore

struct RootView: View {
    @EnvironmentObject private var health: HealthViewModel
    @AppStorage("onboardingComplete") private var onboardingComplete = false
    @AppStorage("themePreference") private var themePreference: AppThemePreference = .system
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showOnboarding = false
    @State private var selectedTab = 0

    /// UI-test launch arguments win; otherwise the stored preference;
    /// otherwise the system. Changing it never reloads cards or resets
    /// navigation — it only changes the trait the colors resolve against.
    private var resolvedColorScheme: ColorScheme? {
        ThemeResolver.resolvedColorScheme(preference: themePreference)
    }

    /// V3 theme transitions are 180–240ms; Reduce Motion makes them static.
    private var themeAnimation: Animation? {
        if reduceMotion { return nil }
        return .easeInOut(duration: 0.2)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            TodayView(onOpenSleepTab: { selectedTab = 2 })
                .tabItem { Label("今日", systemImage: "square.grid.2x2.fill") }
                .tag(0)
            HeartView().tabItem { Label("心脏", systemImage: "heart.text.square.fill") }.tag(1)
            SleepView().tabItem { Label("睡眠", systemImage: "moon.stars.fill") }.tag(2)
            RecordsView().tabItem { Label("健康库", systemImage: "cross.case.fill") }.tag(3)
            ReportView().tabItem { Label("报告", systemImage: "doc.text.image.fill") }.tag(4)
        }
        .tint(HealthTheme.v4Accent)
        .preferredColorScheme(resolvedColorScheme)
        .dynamicTypeSizeIfPresent(ThemeResolver.forcedDynamicTypeSize)
        .animation(themeAnimation, value: resolvedColorScheme)
        .sheet(isPresented: $showOnboarding) {
            // The sheet is a separate presentation context: environment
            // modifiers on the TabView do not reliably reach it (large
            // text showed 0.06% diff on welcome in #50 while dark mode
            // worked). Apply the forced modes directly to the sheet content.
            WelcomeHealthView()
                .preferredColorScheme(resolvedColorScheme)
                .dynamicTypeSizeIfPresent(ThemeResolver.forcedDynamicTypeSize)
        }
        .onAppear {
            // Screenshot-test hook: reset onboarding so each display mode
            // starts at the welcome screen. Only active when the test
            // passes -resetOnboardingForScreenshots as a launch argument.
            if ProcessInfo.processInfo.arguments.contains("-resetOnboardingForScreenshots") {
                onboardingComplete = false
            }
            if onboardingComplete == false { showOnboarding = true }
        }
        .alert("提示", isPresented: Binding(
            get: { health.message != nil },
            set: { if $0 == false { health.message = nil } }
        )) {
            Button("好的", role: .cancel) { health.message = nil }
        } message: { Text(health.message ?? "") }
    }
}

/// Applies `.dynamicTypeSize` only when a size is forced (screenshot tests).
/// When nil the view is returned unchanged so normal launches keep the
/// user's system text size instead of being pinned to `.large`.
private extension View {
    @ViewBuilder
    func dynamicTypeSizeIfPresent(_ size: DynamicTypeSize?) -> some View {
        if let size {
            self.dynamicTypeSize(size)
        } else {
            self
        }
    }
}
