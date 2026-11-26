import Foundation

extension ECGSummary {
    /// A local, user-shareable transcript of this single HealthKit recording.
    public func report(trace: ECGWaveform, timeZone: TimeZone) -> String {
        let date = DateFormatter()
        date.locale = Locale(identifier: "zh_CN")
        date.timeZone = timeZone
        date.dateFormat = "yyyy年M月d日 HH:mm:ss"
        var lines = [
            "心电记录摘要",
            "测量时间　\(date.string(from: recordedAt))（\(timeZone.identifier)）",
            "记录来源　\(source ?? "未提供")",
            "系统分类　\(classification)"
        ]
        if let duration {
            lines.append(String(format: "记录时长　%.1f 秒", duration))
        }
        if let rate = averageHeartRate, rate.isFinite {
            lines.append(String(format: "记录平均心率　%.1f 次/分", rate))
        }
        if let frequency = trace.samplingFrequency {
            lines.append(String(format: "设备报告采样率　%.2f Hz", frequency))
        }
        if let start = trace.samples.first, let end = trace.samples.last {
            lines.append(String(format: "首末采样时差　%.3f 秒", end.seconds - start.seconds))
        }
        lines.append("采样点数　\(trace.samples.count)")
        lines.append("绘图识别的时间间断　\(trace.gapCount) 处")
        lines.append("系统分类仅对应这一次测量。")
        return lines.joined(separator: "\n")
    }
}
