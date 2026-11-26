import SwiftUI
import Charts

struct PPGCaptureView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var capture = PPGCameraCapture()

    @State private var showHelp = false

    var body: some View {
        Form {
            if !capture.busy {
                Section("正确放置手指") { PPGFingerPlacementGuide() }
            }
            Section("相机采集 · 实验功能") {
                Text("画面仅在本机提取亮度变化，随后释放。结果是实验性光学估算；手指移动、环境光和相机设置会影响读数。")
                    .font(.footnote)
                if capture.busy {
                    Label("请完整覆盖镜头和补光灯，保持手指稳定。", systemImage: "hand.raised")
                    Button("停止采集", role: .cancel) { capture.stop() }
                } else {
                    Button("开始采集") { capture.start() }
                }
                Text(capture.message).accessibilityLabel("采集状态，\(capture.message)")
            }
            if let first = capture.waveform.first {
                Section("指尖光学波形") {
                    Chart(capture.waveform, id: \.timestamp) { frame in
                        LineMark(
                            x: .value("时间（秒）", frame.timestamp - first.timestamp),
                            y: .value("红通道亮度", frame.redLevel)
                        )
                    }
                    .chartYScale(domain: .automatic(includesZero: false))
                    .chartXAxisLabel("窗口内时间（秒）")
                    .frame(height: 130)
                    .accessibilityLabel("最近四秒的相机红通道亮度")
                }
            }
            if let estimate = capture.estimate, let shortest = estimate.intervals.min(),
               let longest = estimate.intervals.max() {
                Section("本次脉搏 · 实验估算") {
                    LabeledContent("脉率", value: "\(Int(estimate.beatsPerMinute.rounded())) 次/分")
                    LabeledContent("有效间期", value: "\(estimate.intervals.count) 个")
                    LabeledContent("峰间距", value: "\(Int((shortest * 1000).rounded()))–\(Int((longest * 1000).rounded())) 毫秒")
                    Text("峰间距取自指尖光学信号。与心电 R–R 间期的差异包括脉搏传导时间变化；这段短记录仅供采集研究。")
                        .font(.footnote)
                }
            }
            PPGWatchContextView(acquisition: capture.acquisitionWindow)
                .id(capture.acquisitionWindow)
        }
        .navigationTitle("指尖脉搏信号")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showHelp = true } label: {
                    Label("如何放置手指？", systemImage: "questionmark.circle")
                }
                .disabled(capture.busy)
            }
        }
        .sheet(isPresented: $showHelp) { PPGPlacementHelp() }
        .onDisappear { capture.stop() }
        .onChange(of: phase) { _, phase in
            if phase == .background { capture.stop() }
        }
    }
}
