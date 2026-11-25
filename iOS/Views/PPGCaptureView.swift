import SwiftUI

struct PPGCaptureView: View {
    @Environment(\.scenePhase) private var phase
    @StateObject private var capture = PPGCameraCapture()

    var body: some View {
        Form {
            Section("相机采集 · 实验功能") {
                Text("将指腹轻轻覆盖后置广角镜头和补光灯，保持静止。开始后将开启低亮度补光，约 12 秒自动结束。如有不适，请立即停止。")
                Text("画面仅在本机提取亮度变化，随后释放。结果用于检查采集质量，尚未验证脉率或疾病识别能力。")
                    .font(.footnote)
                if capture.busy {
                    Button("停止采集", role: .cancel) { capture.stop() }
                } else {
                    Button("开始采集") { capture.start() }
                }
                Text(capture.message).accessibilityLabel("采集状态，\(capture.message)")
            }
            PPGWatchContextView()
        }
        .navigationTitle("指尖脉搏信号")
        .onDisappear { capture.stop() }
        .onChange(of: phase) { _, phase in
            if phase == .background { capture.stop() }
        }
    }
}
