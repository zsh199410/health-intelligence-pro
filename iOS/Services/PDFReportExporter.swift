import Foundation
import UIKit
import HealthCore

@MainActor
enum PDFReportExporter {
    static func export(readings: [String: MetricReading], sleep: SleepSummary?,
                       insights: [HealthInsight], failedMetricIDs: [String] = []) throws -> URL {
        let generatedAt = Date()
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("HealthReport-\(UUID().uuidString).pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842))
        let data = renderer.pdfData { context in
            context.beginPage()
            let margin: CGFloat = 42
            var cursor: CGFloat = 48
            func draw(_ text: String, size: CGFloat, bold: Bool = false, tint: UIColor = .label) {
                let font: UIFont = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
                let style = NSMutableParagraphStyle(); style.lineBreakMode = .byWordWrapping
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font, .foregroundColor: tint, .paragraphStyle: style
                ]
                let maxWidth = 595 - margin * 2
                let bounds = (text as NSString).boundingRect(
                    with: CGSize(width: maxWidth, height: 1200),
                    options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes, context: nil)
                let requiredHeight = max(ceil(bounds.height), size + 4)
                if cursor + requiredHeight > 805 {
                    context.beginPage(); cursor = 48
                }
                (text as NSString).draw(in: CGRect(x: margin, y: cursor, width: maxWidth, height: requiredHeight + 3),
                                        withAttributes: attributes)
                cursor += requiredHeight + 10
            }
            draw("健康中枢 · 个人健康摘要", size: 22, bold: true)
            draw("生成于 \(ChineseDateTime.full(generatedAt)) · 来自本机 HealthKit 记录", size: 10)
            if let earliest = readings.values.map(\.recordedAt).min(),
               let latest = readings.values.map(\.recordedAt).max() {
                draw("指标记录时间范围：\(ChineseDateTime.full(earliest)) – \(ChineseDateTime.full(latest))", size: 10)
            } else {
                draw("指标记录时间范围：没有可用记录", size: 10)
            }
            draw("仅供个人健康趋势整理，不用于医学诊断、急救决策或代替专业建议。", size: 10)
            cursor += 8
            draw("主要健康指标", size: 16, bold: true)
            if readings.isEmpty { draw("暂无可读取数据。", size: 12) }
            for metric in HealthCatalog.all {
                guard let value = readings[metric.id] else { continue }
                draw("\(metric.name)：\(metric.display(value.value)) \(value.unit)  [\(ChineseDateTime.full(value.recordedAt))]", size: 11)
            }
            let missing = HealthCatalog.all.filter { readings[$0.id] == nil }
            if !missing.isEmpty {
                draw("缺失的指标（共 \(missing.count) 项，没有可用记录）", size: 13, bold: true)
                draw("没有可用记录不代表指标正常，可能是未授权、未测量或设备不支持。HealthKit 读取为空不能据此推断授权状态。", size: 10)
                for metric in missing { draw("· \(metric.name)", size: 11) }
            }
            if !failedMetricIDs.isEmpty {
                draw("读取失败（共 \(failedMetricIDs.count) 项）", size: 13, bold: true)
                draw("读取过程出错，请重试；失败不等于没有记录。", size: 10)
                for id in failedMetricIDs {
                    draw("· \(HealthCatalog.byID[id]?.name ?? id)", size: 11)
                }
            }
            cursor += 10
            if let sleep, sleep.totalAsleepMinutes > 0 {
                draw("睡眠分期记录：\(sleep.totalAsleepMinutes / 60) 小时 \(sleep.totalAsleepMinutes % 60) 分", size: 13, bold: true)
            }
            draw("本地规则解读", size: 16, bold: true)
            for item in insights {
                draw(item.title, size: 12, bold: true)
                draw(item.body, size: 11)
            }
            cursor += 6
            draw("免责声明：此报告不预测疾病风险。数据缺失不代表指标正常，智能分析不是医嘱。", size: 10)
        }
        try data.write(to: destination, options: [.atomic, .completeFileProtection])
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        var finalURL = destination
        try? finalURL.setResourceValues(values)
        return destination
    }
}
