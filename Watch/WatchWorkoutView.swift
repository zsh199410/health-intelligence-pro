import SwiftUI
import HealthKit
import HealthCore

private enum WorkoutPalette {
    private static func color(_ token: HealthDesignTokens.Token) -> Color {
        let rgb = token.dark
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    static let accent = color(HealthDesignTokens.teal)
    static let heart = color(HealthDesignTokens.heart)
    static let amber = color(HealthDesignTokens.amber)
    static let secondary = Color.white.opacity(0.68)
}

struct WatchWorkoutView: View {
    @EnvironmentObject private var workout: WatchWorkoutManager
    @State private var isEndConfirmationPresented = false
    @State private var isDiscardConfirmationPresented = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 7) {
                    Image(systemName: "figure.run.circle.fill")
                        .foregroundStyle(WorkoutPalette.accent)
                    Text("实时训练")
                        .font(.headline.weight(.bold))
                }

                switch workout.phase {
                case .idle:
                    startChoices
                case .finished:
                    finishedSummary
                    startChoices
                case .saveFailed:
                    saveFailedSummary
                case .starting, .running, .paused, .ending:
                    liveSummary
                    controls
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .navigationTitle("训练")
        .containerBackground(.black, for: .navigation)
        .confirmationDialog("结束并保存这次训练？", isPresented: $isEndConfirmationPresented) {
            Button("结束训练", role: .destructive) { workout.end() }
        } message: {
            Text("训练记录将保存到 Apple 健康。")
        }
        .confirmationDialog("放弃未保存的训练？", isPresented: $isDiscardConfirmationPresented) {
            Button("放弃未保存记录", role: .destructive) { workout.discardUnsavedWorkout() }
        } message: {
            Text("放弃后无法从本 App 恢复这次训练。")
        }
        .alert("训练提示", isPresented: Binding(
            get: { workout.errorMessage != nil },
            set: { if !$0 { workout.errorMessage = nil } }
        )) {
            Button("好的", role: .cancel) { workout.errorMessage = nil }
        } message: {
            Text(workout.errorMessage ?? "")
        }
    }

    private var startChoices: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("选择真实运动后开始记录。心率仅在训练会话中持续更新。")
                .font(.footnote)
                .foregroundStyle(WorkoutPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            startButton("步行", symbol: "figure.walk", activity: .walking)
            startButton("跑步", symbol: "figure.run", activity: .running)
            startButton("其他训练", symbol: "figure.mixed.cardio", activity: .other)
        }
    }

    private func startButton(_ title: String, symbol: String, activity: HKWorkoutActivityType) -> some View {
        Button {
            Task { await workout.start(activity) }
        } label: {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .tint(WorkoutPalette.accent)
        .accessibilityHint("开始记录\(title)训练，并在结束后保存到 Apple 健康")
    }

    private var liveSummary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(phaseText, systemImage: workout.phase == .paused ? "pause.circle.fill" : "record.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(workout.phase == .paused ? WorkoutPalette.amber : WorkoutPalette.accent)
                .accessibilityAddTraits(.updatesFrequently)

            VStack(alignment: .leading, spacing: 4) {
                Text("训练时长")
                    .font(.caption2)
                    .foregroundStyle(WorkoutPalette.secondary)
                Text(durationText(workout.elapsedTime))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
                    .accessibilityLabel("训练时长，\(accessibleDuration(workout.elapsedTime))")
            }

            VStack(alignment: .leading, spacing: 5) {
                Label("心率", systemImage: "heart.fill")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(WorkoutPalette.heart)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(workout.heartRate.map { String(Int($0.rounded())) } ?? "—")
                        .font(.system(.largeTitle, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .minimumScaleFactor(0.7)
                    Text("次/分")
                        .font(.caption2)
                        .foregroundStyle(WorkoutPalette.secondary)
                }
                Text(heartRateStatus)
                    .font(.caption2)
                    .foregroundStyle(workout.hasRecentHeartRate ? WorkoutPalette.secondary : WorkoutPalette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heartRateAccessibilityLabel)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    @ViewBuilder
    private var controls: some View {
        if workout.phase == .running {
            Button { workout.pause() } label: {
                Label("暂停训练", systemImage: "pause.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        } else if workout.phase == .paused {
            Button { workout.resume() } label: {
                Label("继续训练", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkoutPalette.accent)
        }
        if workout.phase == .running || workout.phase == .paused {
            Button(role: .destructive) { isEndConfirmationPresented = true } label: {
                Label("结束并保存", systemImage: "stop.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        if workout.phase == .starting || workout.phase == .ending {
            ProgressView(phaseText)
                .font(.caption)
                .frame(maxWidth: .infinity)
        }
    }

    private var finishedSummary: some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(workout.saveConfirmed ? "训练已保存" : "训练已结束，保存待核对",
                  systemImage: workout.saveConfirmed ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(workout.saveConfirmed ? WorkoutPalette.accent : WorkoutPalette.amber)
                .font(.caption.weight(.semibold))
            if let duration = workout.completedDuration {
                Text("有效时长 \(durationText(duration))")
                    .font(.footnote)
            }
            Text(workout.saveConfirmed
                 ? "可在 Apple 健康中查看记录。"
                 : "设备锁定时可能无法确认保存结果。请解锁后在 Apple 健康中核对。")
                .font(.caption2)
                .foregroundStyle(WorkoutPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var saveFailedSummary: some View {
        VStack(alignment: .leading, spacing: 9) {
            Label("训练尚未保存", systemImage: "exclamationmark.circle.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(WorkoutPalette.amber)
            if let duration = workout.completedDuration {
                Text("有效时长 \(durationText(duration))")
                    .font(.footnote)
            }
            Text("请重试保存。未确认前，训练数据仍保留在当前会话中。")
                .font(.caption2)
                .foregroundStyle(WorkoutPalette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button { workout.retrySaving() } label: {
                Label("重试保存", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WorkoutPalette.accent)
            Button(role: .destructive) { isDiscardConfirmationPresented = true } label: {
                Label("放弃未保存记录", systemImage: "trash")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 16))
    }

    private var phaseText: String {
        switch workout.phase {
        case .idle: return "尚未开始"
        case .starting: return "准备训练中"
        case .running: return "正在记录训练"
        case .paused: return "训练已暂停"
        case .ending: return "正在保存训练"
        case .saveFailed: return "训练尚未保存"
        case .finished: return workout.saveConfirmed ? "训练已保存" : "训练已结束，保存待核对"
        }
    }

    private var heartRateStatus: String {
        guard let date = workout.heartRateRecordedAt else { return "等待手表采集心率" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.dateFormat = "HH:mm:ss"
        let prefix = workout.hasRecentHeartRate ? "测得" : "最近记录"
        return "\(prefix)于 \(formatter.string(from: date)) · 训练会话"
    }

    private var heartRateAccessibilityLabel: String {
        guard let value = workout.heartRate else { return "心率，等待手表采集数据" }
        return "心率，\(Int(value.rounded())) 次每分。\(heartRateStatus)"
    }

    private func durationText(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return String(format: "%02d:%02d:%02d", total / 3600, (total / 60) % 60, total % 60)
    }

    private func accessibleDuration(_ duration: TimeInterval) -> String {
        let total = max(0, Int(duration))
        return "\(total / 3600) 小时 \((total / 60) % 60) 分 \(total % 60) 秒"
    }
}
