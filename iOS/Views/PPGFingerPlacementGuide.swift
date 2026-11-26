import SwiftUI

struct PPGFingerPlacementGuide: View {
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("请将食指指腹轻轻覆盖后置广角镜头和闪光灯，保持静止约 12 秒。")
            let layout = textSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 12))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 12))
            layout {
                example(covered: true)
                example(covered: false)
            }
        }
        .padding(.vertical, 4)
    }

    private func example(covered: Bool) -> some View {
        let color = covered ? HealthTheme.teal : HealthTheme.coral
        return VStack(alignment: .leading, spacing: 5) {
            PlacementDrawing(covered: covered)
                .aspectRatio(1.65, contentMode: .fit)
                .background(HealthTheme.canvas, in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            Label(covered ? "正确放置" : "错误放置",
                  systemImage: covered ? "checkmark.circle.fill" : "xmark.circle")
                .font(.subheadline.weight(.semibold)).foregroundStyle(color)
            Text(covered ? "同时覆盖镜头和灯" : "只遮镜头，补光灯外露")
                .font(.caption).foregroundStyle(HealthTheme.muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

/// Schematic rear view. The translucent pad lets both contact targets remain visible.
private struct PlacementDrawing: View {
    let covered: Bool

    var body: some View {
        Canvas { context, size in
            let scale = min(size.width / 160, size.height / 98)
            context.translateBy(x: (size.width - 160 * scale) / 2, y: (size.height - 98 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            let phone = Path(roundedRect: CGRect(x: 49, y: 4, width: 60, height: 90), cornerRadius: 10)
            context.fill(phone, with: .color(HealthTheme.surface))
            context.stroke(phone, with: .color(HealthTheme.muted), lineWidth: 1.5)
            let module = Path(roundedRect: CGRect(x: 53, y: 9, width: 48, height: 31), cornerRadius: 7)
            context.stroke(module, with: .color(HealthTheme.line), lineWidth: 1.5)
            let lens = Path(ellipseIn: CGRect(x: 57, y: 14, width: 20, height: 20))
            context.fill(lens, with: .color(HealthTheme.ink))
            context.stroke(Path(ellipseIn: CGRect(x: 63, y: 20, width: 8, height: 8)),
                           with: .color(HealthTheme.surface), lineWidth: 1.4)
            let flash = Path(ellipseIn: CGRect(x: 84, y: 19, width: 10, height: 10))
            context.fill(flash, with: .color(HealthTheme.amber))
            context.stroke(flash, with: .color(HealthTheme.ink), lineWidth: 1)
            let tip: CGFloat = covered ? 99 : 80
            let tint = covered ? HealthTheme.teal : HealthTheme.coral
            var pad = Path()
            pad.move(to: CGPoint(x: 15, y: 43))
            pad.addLine(to: CGPoint(x: tip - 18, y: 12))
            pad.addQuadCurve(to: CGPoint(x: tip, y: 22), control: CGPoint(x: tip + 1, y: 5))
            pad.addQuadCurve(to: CGPoint(x: tip - 12, y: 37), control: CGPoint(x: tip + 1, y: 31))
            pad.addLine(to: CGPoint(x: 26, y: 66))
            context.fill(pad, with: .color(tint.opacity(0.23)))
            context.stroke(pad, with: .color(tint), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
        }
    }
}

struct PPGPlacementHelp: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("正确放置手指") { PPGFingerPlacementGuide() }
                Section("测量时") {
                    Label("指腹轻贴即可，避免用力按压。", systemImage: "hand.point.up.left")
                    Label("支撑好手机和手臂，保持手指稳定。", systemImage: "iphone")
                    Label("若提示信号差，请重新放置后再测量。如感到不适，可立即停止。", systemImage: "arrow.counterclockwise")
                }
            }
            .navigationTitle("如何放置手指？")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
