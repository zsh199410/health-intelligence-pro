import SwiftUI
import HealthCore

@main
struct HealthWatchApp: App {
    @StateObject private var store = WatchHealthStore()
    var body: some Scene {
        WindowGroup { WatchDashboard().environmentObject(store) }
    }
}

/// Watch colors resolve from the same HealthDesignTokens as the iPhone app.
/// watchOS has no UIColor dynamic provider and no userInterfaceStyle, so
/// there is no dynamic resolution here: the Watch interface is always dark,
/// and the dark value applies.
private enum WatchPalette {
    static func color(_ token: HealthDesignTokens.Token) -> Color {
        let rgb = token.dark
        return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    static let mint = color(HealthDesignTokens.teal)
    static let pink = color(HealthDesignTokens.heart)
    static let amber = color(HealthDesignTokens.amber)
    static let secondary = Color.white.opacity(0.60)
    /// Pulse card background: decorative dark gradient, not a semantic color.
    static let pulseTop = Color(red: 0.22, green: 0.13, blue: 0.19)
    static let pulseBottom = Color(red: 0.11, green: 0.12, blue: 0.15)
}

struct WatchDashboard: View {
    @EnvironmentObject private var store: WatchHealthStore
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("健康中枢").font(.headline.weight(.bold)).foregroundStyle(.white)
                        Text("手表健康").font(.system(size: 9, weight: .bold))
                            .tracking(1.4).foregroundStyle(WatchPalette.mint)
                    }
                    Spacer()
                    Image(systemName: "heart.text.square.fill").foregroundStyle(WatchPalette.mint)
                }
                pulseCard
                HStack(spacing: 8) {
                    smallCard("HRV", id: "hrv", unit: "ms", symbol: "waveform.path.ecg")
                    smallCard("血氧", id: "oxygenSaturation", unit: "%", symbol: "lungs.fill")
                }
                HStack(spacing: 8) {
                    smallCard("呼吸频率", id: "respiratoryRate", unit: "次/分", symbol: "wind")
                    smallCard("静息心率", id: "restingHeartRate", unit: "次/分", symbol: "heart.text.square")
                }
                // Screenshot-test hook: launched with -watchScreenshotSleep,
                // the dashboard opens scrolled to the sleep section so the
                // sleep shot is a real app screen, not a scrolled guess.
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Label("昨夜睡眠", systemImage: "moon.stars.fill")
                            .font(.caption.weight(.semibold)).foregroundStyle(WatchPalette.mint)
                        Spacer()
                        if let sleep = store.sleep, sleep.totalAsleepMinutes > 0 {
                            Text("\(sleep.totalAsleepMinutes / 60)小时\(sleep.totalAsleepMinutes % 60)分")
                                .font(.caption.weight(.bold)).foregroundStyle(.white)
                        } else {
                            Text("暂无记录").font(.caption2).foregroundStyle(WatchPalette.secondary)
                        }
                    }
                    if let window = store.sleepWindow {
                        Text("\(WatchChineseDateTime.time(window.lowerBound)) – \(WatchChineseDateTime.time(window.upperBound))")
                            .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1)
                    }
                    if let sleep = store.sleep, sleep.totalAsleepMinutes > 0 {
                        GeometryReader { geo in
                            HStack(spacing: 2) {
                                ForEach(SleepStage.allCases, id: \.self) { stage in
                                    let minutes = sleep.minutesByStage[stage, default: 0]
                                    if minutes > 0 {
                                        RoundedRectangle(cornerRadius: 2)
                                            .fill(stageColor(stage))
                                            .frame(width: max(1, geo.size.width * CGFloat(minutes) / CGFloat(max(1, sleep.totalAsleepMinutes + sleep.minutesAwake)) - 2))
                                    }
                                }
                            }
                        }.frame(height: 7)
                    }
                }.padding(11)
                 .frame(maxWidth: .infinity, alignment: .leading)
                 .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
                 .id("sleepSection")
                if store.isLoading { ProgressView().frame(maxWidth: .infinity) }
                Button { Task { await store.authorize() } } label: {
                    Label("授权健康数据", systemImage: "lock.open.fill")
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }.buttonStyle(.borderedProminent).tint(WatchPalette.mint).foregroundStyle(.black)
                .disabled(store.isLoading)
                Button { Task { await store.refresh() } } label: {
                    Label("刷新记录", systemImage: "arrow.clockwise")
                        .font(.caption.weight(.semibold)).frame(maxWidth: .infinity)
                }.buttonStyle(.bordered).disabled(store.isLoading)
                Text("仅显示已有系统记录，非实时医疗监护。")
                    .font(.system(size: 10)).foregroundStyle(WatchPalette.secondary)
            }.padding(.horizontal, 8).padding(.bottom, 10)
        }
        .onAppear {
            if ProcessInfo.processInfo.arguments.contains("-watchScreenshotSleep") {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    withAnimation { proxy.scrollTo("sleepSection", anchor: .top) }
                }
            }
        }
        .containerBackground(.black, for: .navigation)
        .alert("提示", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) { Button("好的", role: .cancel) { store.errorMessage = nil } }
        message: { Text(store.errorMessage ?? "") }
        }
    }
    private func stageColor(_ stage: SleepStage) -> Color {
        WatchPalette.color(HealthDesignTokens.stageToken(for: stage))
    }

    private var pulseCard: some View {
        let reading = store.readings["heartRate"]
        let stale = isStale(reading)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Label("心率", systemImage: "heart.fill")
                    .font(.caption).foregroundStyle(WatchPalette.pink)
                Spacer()
                Text(stale ? "数据较旧" : "上次记录")
                    .font(.system(size: 9)).foregroundStyle(stale ? WatchPalette.amber : WatchPalette.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(reading.map { String(Int($0.value.rounded())) } ?? "—")
                    .font(.system(size: 36, weight: .bold, design: .rounded)).foregroundStyle(.white)
                    .minimumScaleFactor(0.7).lineLimit(1)
                Text("BPM").font(.caption2).foregroundStyle(WatchPalette.secondary)
                Spacer()
                Image(systemName: "waveform.path.ecg")
                    .font(.title3).foregroundStyle(WatchPalette.pink)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.map { "上次记录 \(WatchChineseDateTime.full($0.recordedAt))" } ?? "暂无记录")
                    .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Text(reading.map { $0.source.isEmpty ? "来源未知" : $0.source } ?? "来源 —")
                    .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
        }.padding(13)
         .frame(maxWidth: .infinity, alignment: .leading)
         .background(LinearGradient(colors: [WatchPalette.pulseTop, WatchPalette.pulseBottom], startPoint: .topLeading, endPoint: .bottomTrailing),
                     in: RoundedRectangle(cornerRadius: 18))
         .accessibilityElement(children: .combine)
         .accessibilityLabel(voiceOverLabel(id: "heartRate", title: "心率", unit: "次每分", reading: reading))
    }
    private func smallCard(_ title: String, id: String, unit: String, symbol: String) -> some View {
        let reading = store.readings[id]
        let stale = isStale(reading)
        return VStack(alignment: .leading, spacing: 6) {
            Image(systemName: symbol).foregroundStyle(WatchPalette.mint).font(.caption)
            Text(title).font(.system(size: 10)).foregroundStyle(WatchPalette.secondary).lineLimit(1)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(reading.map { String(format: "%.1f", $0.value) } ?? "—")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .minimumScaleFactor(0.6).lineLimit(1)
                if reading != nil {
                    Text(unit).font(.system(size: 8)).foregroundStyle(WatchPalette.secondary).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(reading.map { (stale ? "较旧 · " : "") + "上次记录 " + relativeTime($0.recordedAt) } ?? "暂无记录")
                    .font(.caption2).foregroundStyle(stale ? WatchPalette.amber : WatchPalette.secondary)
                    .lineLimit(1).minimumScaleFactor(0.6)
                Text(reading.map { $0.source.isEmpty ? "来源未知" : $0.source } ?? "来源 —")
                    .font(.caption2).foregroundStyle(WatchPalette.secondary).lineLimit(1).minimumScaleFactor(0.6)
            }
            Spacer(minLength: 0)
        }
        .padding(11).frame(maxWidth: .infinity, minHeight: 91, alignment: .leading)
        .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 15))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(voiceOverLabel(id: id, title: title, unit: unit, reading: reading))
    }

    /// A reading older than 24 hours is flagged as stale, in text as well as color.
    private func isStale(_ reading: MetricReading?) -> Bool {
        guard let reading else { return false }
        return Date().timeIntervalSince(reading.recordedAt) > 24 * 3600
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private func voiceOverLabel(id: String, title: String, unit: String, reading: MetricReading?) -> String {
        guard let reading else { return "\(title)，暂无记录" }
        let integerIDs = ["heartRate", "restingHeartRate"]
        let value = integerIDs.contains(id) ? String(Int(reading.value.rounded())) : String(format: "%.1f", reading.value)
        let time = WatchChineseDateTime.full(reading.recordedAt)
        let source = reading.source.isEmpty ? "来源未知" : reading.source
        let stale = isStale(reading) ? "，数据较旧" : ""
        return "\(title)，\(value) \(unit)，上次记录 \(time)，来源 \(source)\(stale)"
    }
}

/// Watch target uses its own formatter because iOS-only files are not linked.
private enum WatchChineseDateTime {
    static func full(_ date: Date) -> String { format(date, pattern: "M月d日 HH:mm") }
    static func time(_ date: Date) -> String { format(date, pattern: "HH:mm") }

    private static func format(_ date: Date, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_Hans_CN")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }
}
