import SwiftUI
import UIKit

@MainActor
final class HealthLaunchDelegate: NSObject, UIApplicationDelegate {
    let health = HealthViewModel()

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        health.registerForBackgroundDeliveryAtLaunch()
        return true
    }
}

@main
struct HealthIntelligenceApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @UIApplicationDelegateAdaptor(HealthLaunchDelegate.self) private var launchDelegate
    @StateObject private var journal = JournalStore()

    init() { _ = WatchStatusReceiver.shared }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(launchDelegate.health)
                .environmentObject(journal)
                // Keep SwiftUI dates, calendars and system controls in Simplified Chinese
                // regardless of the iPhone display-language setting.
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .tint(HealthTheme.v4Accent)
                .task { launchDelegate.health.resumeFromForeground() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active { launchDelegate.health.resumeFromForeground() }
                }
        }
    }
}
