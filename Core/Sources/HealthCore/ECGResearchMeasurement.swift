import Foundation

/// Cursors refer to unmodified samples from one recording. Do not pass chart pixel indices.
public struct ECGCaliper: Equatable, Sendable {
    public let start: ECGVoltagePoint
    public let end: ECGVoltagePoint
    public var elapsedMilliseconds: Double { (end.seconds - start.seconds) * 1000 }
    public var voltageChangeMillivolts: Double { end.millivolts - start.millivolts }

    public init?(trace: ECGWaveform, startIndex: Int, endIndex: Int) {
        guard startIndex < endIndex, trace.samples.indices.contains(startIndex),
              trace.samples.indices.contains(endIndex),
              trace.samplingFrequency != nil || trace.samples.count >= 4 else { return nil }
        let first = trace.samples[startIndex], last = trace.samples[endIndex]
        // Ask the waveform for its original continuity boundaries regardless of the overview budget.
        guard trace.segments(in: first.seconds...last.seconds, displayBudget: 2).count == 1 else { return nil }
        start = first
        end = last
    }
}

/// Single-lead morphology at manually reviewed landmarks. No automated P/T delineation,
/// ectopy classification or ischemia threshold. Preserve signed amplitudes and lead orientation.
public struct ECGAnnotatedMorphology: Equatable, Sendable {
    public let referenceMillivolts: Double
    public let stChangeMillivolts: Double
    public let stDelayMilliseconds: Double
    public let tPeakChangeMillivolts: Double

    /// reference is an isoelectric segment selected by a reviewer. jPoint, stCursor and tPeak
    /// must be annotated on the same beat; the caller must verify ST lies before T onset.
    public init?(trace: ECGWaveform, reference: ClosedRange<Int>, jPoint: Int, stCursor: Int, tPeak: Int) {
        guard trace.samples.indices.contains(reference.lowerBound), trace.samples.indices.contains(reference.upperBound),
              reference.count >= 3, reference.upperBound < jPoint, jPoint < stCursor, stCursor < tPeak,
              ECGCaliper(trace: trace, startIndex: reference.lowerBound, endIndex: tPeak) != nil else { return nil }
        let values = trace.samples[reference].map(\.millivolts).sorted()
        let middle = values.count / 2
        referenceMillivolts = values.count.isMultiple(of: 2) ? values[middle - 1] / 2 + values[middle] / 2 : values[middle]
        stChangeMillivolts = trace.samples[stCursor].millivolts - referenceMillivolts
        tPeakChangeMillivolts = trace.samples[tPeak].millivolts - referenceMillivolts
        stDelayMilliseconds = 1000 * (trace.samples[stCursor].seconds - trace.samples[jPoint].seconds)
    }
}

extension ECGSummary {
    /// Takes the same recording's unmodified trace. System classification stays in the original report.
    public func experimentalReport(trace: ECGWaveform, timeZone: TimeZone) -> String {
        var lines = [report(trace: trace, timeZone: timeZone), "实验性逐搏分析"]
        switch ECGBeatDetector.detect(in: trace) {
        case let .failure(reason):
            let detail: String
            switch reason {
            case .insufficientDuration: detail = "连续记录时长不足"
            case .unsupportedCadence: detail = "采样频率超出研究范围"
            case .interruptedSampling: detail = "采样有间断或时钟不稳定"
            case .weakOrNoisySignal: detail = "波形质量不足"
            case .tooFewBeats: detail = "可识别的候选波群过少"
            }
            lines.append("未生成 RR 测量（" + detail + "）。")
        case let .success(beats):
            let intervals = beats.rrIntervals.sorted()
            let mid = intervals.count / 2
            let median = intervals.count.isMultiple(of: 2) ? (intervals[mid - 1] + intervals[mid]) / 2 : intervals[mid]
            lines.append("候选 QRS 波群　\(beats.peakTimes.count) 个")
            lines.append(String(format: "相邻候选峰间期中位数　%.0f 毫秒（%d 对）", median * 1000, intervals.count))
            lines.append("间期可能受漏检、误检及异位搏动影响。")
        }
        lines.append("PR、QRS 时限、QT 与 QTc 需另行标注。此分析无法判定早搏类型或心肌缺血。")
        return lines.joined(separator: "\n")
    }
}
