import SwiftUI

@main
struct HealthIntelligenceApp: App {
    @StateObject private var health = HealthViewModel()
    @StateObject private var journal = JournalStore()

    init() { _ = WatchStatusReceiver.shared }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(health)
                .environmentObject(journal)
                // Keep SwiftUI dates, calendars and system controls in Simplified Chinese
                // regardless of the iPhone display-language setting.
                .environment(\.locale, Locale(identifier: "zh_Hans_CN"))
                .tint(HealthTheme.teal)
        }
    }
}
