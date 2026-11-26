import SwiftUI

/// 指尖脉搏采集放置示意图：纯 SwiftUI 矢量绘制，不含图片资源。
/// 事实口径（codex/phase3-waveform，PPGCameraCapture.swift）：
/// 后置广角镜头（.builtInWideAngleCamera，position: .back）＋闪光灯作补光（手电，0.1 亮度）。
/// 机型布局按 iPhone 16 Pro Max 背面：三摄三角布局，广角左上、超广角左下、长焦右侧，
/// 闪光灯在相机台右上、激光雷达在右下。图示只作方位示意，标签以功能为准。
enum PPGFingertipPlacement {
    case correct
    case lensOnly
    case flashOnly
    case tilted
    case pressed
    case moving
}

struct PPGPhoneBackDiagramView: View {
    var placement: PPGFingertipPlacement = .correct
    var showLabels: Bool = true

    var body: some View {
        ZStack {
            phoneBody
            cameraPlateau
            lensView(center: CGPoint(x: 50, y: 50), radius: 16, highlighted: true)
            lensView(center: CGPoint(x: 50, y: 104), radius: 16, highlighted: false)
            lensView(center: CGPoint(x: 104, y: 77), radius: 16, highlighted: false)
            flashView
            lidarView
            fingertip
            if showLabels {
                labels
            }
        }
        .frame(width: 320, height: 400)
        .accessibilityLabel("手机背面示意图：后置广角镜头在左上，闪光灯在右上")
    }

    private var phoneBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28)
                .fill(Color(.secondarySystemBackground))
                .frame(width: 180, height: 380)
            RoundedRectangle(cornerRadius: 28)
                .stroke(Color.primary.opacity(0.25), lineWidth: 1)
                .frame(width: 180, height: 380)
        }
        .position(x: 100, y: 200)
    }

    private var cameraPlateau: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.tertiarySystemBackground))
                .frame(width: 110, height: 110)
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.primary.opacity(0.2), lineWidth: 1)
                .frame(width: 110, height: 110)
        }
        .position(x: 77, y: 77)
    }

    private func lensView(center: CGPoint, radius: CGFloat, highlighted: Bool) -> some View {
        ZStack {
            Circle()
                .fill(Color(.systemBackground))
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .stroke(highlighted ? Color.accentColor : Color.primary.opacity(0.35), lineWidth: highlighted ? 2 : 1)
                .frame(width: radius * 2, height: radius * 2)
            Circle()
                .fill(Color.primary.opacity(0.5))
                .frame(width: radius, height: radius)
            Circle()
                .fill(Color.white.opacity(0.7))
                .frame(width: radius * 0.35, height: radius * 0.35)
                .offset(x: -radius * 0.25, y: -radius * 0.25)
        }
        .position(center)
    }

    private var flashView: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(Color.yellow.opacity(0.85))
            .frame(width: 22, height: 12)
            .position(x: 104, y: 38)
    }

    private var lidarView: some View {
        Circle()
            .fill(Color.primary.opacity(0.35))
            .frame(width: 14, height: 14)
            .position(x: 104, y: 112)
    }

    @ViewBuilder
    private var fingertip: some View {
        switch placement {
        case .correct:
            fingertipShape(center: CGPoint(x: 77, y: 44), width: 100, height: 48, rotation: 0, ghost: false)
        case .lensOnly:
            fingertipShape(center: CGPoint(x: 50, y: 50), width: 54, height: 50, rotation: 0, ghost: false)
        case .flashOnly:
            fingertipShape(center: CGPoint(x: 104, y: 38), width: 54, height: 42, rotation: 0, ghost: false)
        case .tilted:
            fingertipShape(center: CGPoint(x: 77, y: 44), width: 100, height: 48, rotation: 28, ghost: false)
        case .pressed:
            fingertipShape(center: CGPoint(x: 77, y: 44), width: 110, height: 30, rotation: 0, ghost: false)
            Image(systemName: "chevron.down")
                .foregroundStyle(Color.red)
                .position(x: 60, y: 12)
            Image(systemName: "chevron.down")
                .foregroundStyle(Color.red)
                .position(x: 94, y: 12)
        case .moving:
            fingertipShape(center: CGPoint(x: 62, y: 44), width: 100, height: 48, rotation: 0, ghost: true)
            fingertipShape(center: CGPoint(x: 92, y: 44), width: 100, height: 48, rotation: 0, ghost: false)
        }
    }

    private func fingertipShape(center: CGPoint, width: CGFloat, height: CGFloat, rotation: Double, ghost: Bool) -> some View {
        Capsule()
            .fill(Color.accentColor.opacity(ghost ? 0.07 : 0.18))
            .overlay(Capsule().stroke(Color.accentColor.opacity(ghost ? 0.3 : 0.8), lineWidth: 1.5))
            .frame(width: width, height: height)
            .rotationEffect(.degrees(rotation))
            .position(center)
    }

    private var labels: some View {
        Group {
            Path { path in
                path.move(to: CGPoint(x: 68, y: 50))
                path.addLine(to: CGPoint(x: 192, y: 62))
            }
            .stroke(Color.secondary, lineWidth: 1)
            Text("后置广角镜头")
                .font(.caption)
                .position(x: 252, y: 62)
            Path { path in
                path.move(to: CGPoint(x: 116, y: 38))
                path.addLine(to: CGPoint(x: 192, y: 28))
            }
            .stroke(Color.secondary, lineWidth: 1)
            Text("闪光灯 · 0.1 亮度补光")
                .font(.caption)
                .position(x: 252, y: 28)
            Path { path in
                path.move(to: CGPoint(x: 127, y: 44))
                path.addLine(to: CGPoint(x: 192, y: 44))
            }
            .stroke(Color.secondary, lineWidth: 1)
            Text("指腹")
                .font(.caption)
                .bold()
                .position(x: 252, y: 44)
        }
    }
}

struct PPGCaptureGuideView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("正确放置手指")
                    .font(.title2)
                    .bold()
                PPGPhoneBackDiagramView(placement: .correct, showLabels: true)
                    .frame(maxWidth: .infinity)
                Text("请将食指指腹轻轻覆盖后置广角镜头和闪光灯，保持静止约 12 秒。")
                    .font(.body)
                VStack(alignment: .leading, spacing: 10) {
                    Text("同时做到")
                        .font(.headline)
                    bulletRow(text: "同时覆盖镜头和补光灯", correct: true)
                    bulletRow(text: "不要按压过重", correct: true)
                    bulletRow(text: "保持手指稳定不移动", correct: true)
                    bulletRow(text: "若提示信号差，请重新放置后再测量", correct: true)
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("正确放置")
                        .font(.headline)
                    HStack(alignment: .center, spacing: 12) {
                        PPGPhoneBackDiagramView(placement: .correct, showLabels: false)
                            .scaleEffect(0.25)
                            .frame(width: 80, height: 100)
                        VStack(alignment: .leading, spacing: 6) {
                            bulletRow(text: "指腹完整覆盖镜头和闪光灯", correct: true)
                            bulletRow(text: "手指轻放", correct: true)
                            bulletRow(text: "保持静止", correct: true)
                            bulletRow(text: "约 12 秒自动结束", correct: true)
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("错误放置")
                        .font(.headline)
                    wrongRow(placement: .lensOnly, caption: "只盖住镜头，没盖住闪光灯")
                    wrongRow(placement: .flashOnly, caption: "只盖住闪光灯，没盖住镜头")
                    wrongRow(placement: .pressed, caption: "手指压太重")
                    wrongRow(placement: .tilted, caption: "手指倾斜 / 松开漏光")
                    wrongRow(placement: .moving, caption: "采集中移动")
                }
                VStack(alignment: .leading, spacing: 10) {
                    Text("采集中提示")
                        .font(.headline)
                    promptRow(text: "请保持手指稳定")
                    promptRow(text: "请完整覆盖镜头和补光灯")
                    promptRow(text: "检测到抖动，请重新放置")
                    promptRow(text: "信号质量较差，请调整手指位置")
                }
                Text("示意图仅作方位示意；请以本机背面实际镜头与闪光灯位置为准。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
    }

    private func bulletRow(text: String, correct: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if correct {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.green)
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(Color.red)
            }
            Text(text)
            Spacer()
        }
    }

    private func promptRow(text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.secondary)
            Text(text)
            Spacer()
        }
    }

    private func wrongRow(placement: PPGFingertipPlacement, caption: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            PPGPhoneBackDiagramView(placement: placement, showLabels: false)
                .scaleEffect(0.25)
                .frame(width: 80, height: 100)
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(Color.red)
            Text(caption)
            Spacer()
        }
    }
}
