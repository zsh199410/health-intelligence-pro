import Foundation

/// Explicit Chinese date formatting for Date.formatted() call sites.
/// SwiftUI's locale environment does not affect Foundation Date.formatted().
/// Uses the device's current time zone and 24-hour clock.
enum ChineseDateTime {
    static func day(_ date: Date) -> String { format(date, pattern: "yyyy年M月d日 EEEE") }

    static func full(_ date: Date) -> String { format(date, pattern: "yyyy年M月d日 HH:mm") }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
