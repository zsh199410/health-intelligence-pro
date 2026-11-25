import Foundation
import HealthCore

struct PeriodHealthReport {
    struct Row: Identifiable {
        let id: String
        let name: String
        let result: String
        let detail: String
    }

    let period: ReportPeriod
    let rangeText: String
    let rows: [Row]

    static func read(period: ReportPeriod, repository: HealthKitRepository) async throws -> Self {
        let end = Date()
        let calendar = Calendar.current
        let window = period.window(endingAt: end, calendar: calendar)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "yyyy年M月d日 HH:mm"
        let range = "\(formatter.string(from: window.lowerBound)) 至 \(formatter.string(from: end))（\(calendar.timeZone.identifier)）"
        var rows: [Row] = []
        for id in ["restingHeartRate", "hrv", "respiratoryRate", "stepCount", "activeEnergy"] {
            try Task.checkCancellation()
            guard let metric = HealthCatalog.byID[id] else { continue }
            let cumulative = metric.aggregation == .sumToday
            let name = metric.name.replacingOccurrences(of: "今日", with: "")
            let result: String
            let detail: String
            do {
                let points = try await repository.trend(metric, days: period.rawValue, endingAt: end, calendar: calendar)
                if let reading = period.summarize(points, endingAt: end, cumulative: cumulative, calendar: calendar) {
                    result = "\(metric.display(reading.value)) \(metric.unitText)"
                    let method = cumulative ? "有记录日期合计" : "有记录日期的日均值等权平均"
                    detail = "\(method) · \(reading.days)/\(period.rawValue) 天有记录"
                } else {
                    result = "暂无可读取记录"
                    detail = "此时段内未返回数据"
                }
            } catch {
                result = "读取失败"
                detail = "可重新读取此时段"
            }
            rows.append(Row(id: id, name: name, result: result, detail: detail))
        }
        try Task.checkCancellation()
        return Self(period: period, rangeText: range, rows: rows)
    }
}
