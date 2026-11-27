import Charts
import HealthCore
import SwiftUI

/// The detail screen can pass its already-loaded raw trace; this view performs no HealthKit queries.
struct ECGResearchRulerView: View {
    let record: ECGSummary
    let trace: ECGWaveform
    @State private var first = 0
    @State private var second = 1
    @State private var report: String?

    var body: some View {
        List {
            if trace.samples.count >= 2, trace.samples.indices.contains(second) {
                Section("原始波形标尺") {
                    chart
                    cursor("起点", index: $first, range: 0...(second - 1))
                    cursor("终点", index: $second, range: (first + 1)...(trace.samples.count - 1))
                    if let ruler = ECGCaliper(trace: trace, startIndex: first, endIndex: second) {
                        LabeledContent("时间差", value: String(format: "%.1f 毫秒", ruler.elapsedMilliseconds))
                        LabeledContent("终点相对起点电压", value: String(format: "%+.3f 毫伏", ruler.voltageChangeMillivolts))
                    } else {
                        Text("所选波形连续性不足，无法测量。").foregroundStyle(.secondary)
                    }
                }
            } else {
                Text("至少需要两个原始采样点才能使用标尺。")
            }
            Section("本次记录的实验报告") {
                if let report {
                    Text(report).textSelection(.enabled)
                } else {
                    ProgressView("正在分析原始采样…")
                }
            }
        }
        .navigationTitle("心电测量")
        .task(id: record.id) {
            first = 0
            if let start = trace.samples.first {
                second = trace.samples.firstIndex { $0.seconds >= start.seconds + 0.2 }
                    ?? max(1, trace.samples.count - 1)
            }
            report = nil
            let text = await Task.detached(priority: .userInitiated) { [record, trace] in
                record.experimentalReport(trace: trace, timeZone: .current)
            }.value
            if !Task.isCancelled { report = text }
        }
    }

    private func cursor(_ label: String, index: Binding<Int>, range: ClosedRange<Int>) -> some View {
        VStack(alignment: .leading) {
            Stepper(value: index, in: range) {
                Text("\(label)　\(String(format: "%.3f 秒", trace.samples[index.wrappedValue].seconds))")
                    .monospacedDigit()
            }
            if range.lowerBound < range.upperBound {
                Slider(value: Binding(get: { Double(index.wrappedValue) }, set: {
                    index.wrappedValue = min(range.upperBound, max(range.lowerBound, Int($0.rounded())))
                }), in: Double(range.lowerBound)...Double(range.upperBound), step: 1)
                    .accessibilityLabel("移动" + label)
                    .accessibilityValue(String(format: "%.3f 秒", trace.samples[index.wrappedValue].seconds))
            }
        }
    }

    private var chart: some View {
        let left = trace.samples[first].seconds, right = trace.samples[second].seconds
        let window = max(trace.samples[0].seconds, left - 0.2)...min(trace.samples[trace.samples.count - 1].seconds, right + 0.2)
        let runs = trace.segments(in: window, displayBudget: 900)
        return Chart {
            ForEach(runs) { run in
                ForEach(run.points) { point in
                    LineMark(x: .value("时间", point.seconds), y: .value("电压", point.millivolts),
                             series: .value("连续波形", run.id))
                        .foregroundStyle(.primary)
                }
            }
            RuleMark(x: .value("起点", left)).foregroundStyle(.blue)
            RuleMark(x: .value("终点", right)).foregroundStyle(.orange)
                .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 3]))
        }
        .chartXScale(domain: window)
        .chartXAxisLabel("秒")
        .chartYAxisLabel("毫伏")
        .frame(height: 180)
        .accessibilityLabel("原始心电波形，蓝色实线为起点，橙色虚线为终点")
    }
}
