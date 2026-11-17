import Foundation

/// Absolute-time layout for the V3 sleep stage timeline (GPT review B1,
/// Draft PR #4). Converts the deduplicated `SleepCalculator.segments`
/// output into runs positioned by absolute time inside the session
/// window, so a gap in the data renders as a blank unrecorded run
/// instead of being squeezed out.
///
/// Every run's x and width follow GPT's formula exactly:
/// `x = (segment.start - window.lowerBound) / windowSeconds * width`,
/// `width = duration / windowSeconds * width`. There is no inter-run
/// spacing and no minimum-width bump: the old `HStack(spacing: 2)`
/// plus `max(2, …)` minimum widths could exceed the bar when many
/// short segments stacked up, while exact absolute positions tile the
/// bar by construction and can never overflow. A very short segment
/// renders as a thin sliver — honest, since the legend next to the bar
/// carries the same minutes as text. All coordinates are pure values
/// — no UI — so the layout is unit-testable.
public enum SleepTimelineLayout {
    /// One horizontal run of the timeline bar. `stage == nil` is an
    /// unrecorded gap: render it as blank/neutral, never as "awake".
    public struct Run: Equatable, Sendable {
        public let x: Double
        public let width: Double
        public let stage: SleepStage?
        public let start: Date
        public let end: Date

        public init(x: Double, width: Double, stage: SleepStage?, start: Date, end: Date) {
            self.x = x
            self.width = width
            self.stage = stage
            self.start = start
            self.end = end
        }
    }

    /// Tile `segments` across `width` points of the `window`, inserting
    /// a `stage == nil` run for every unrecorded gap (including the
    /// leading/trailing gap when the first/last segment does not touch
    /// the window edge). Segments are clamped to the window and to each
    /// other, so overlapping or out-of-window input cannot overflow.
    /// Returns [] when the window or the width is not positive.
    public static func runs(segments: [SleepInterval], window: ClosedRange<Date>, width: Double) -> [Run] {
        let windowSeconds = window.upperBound.timeIntervalSince(window.lowerBound)
        guard windowSeconds > 0, width > 0 else { return [] }
        let sorted = segments.filter { $0.end > $0.start }.sorted { $0.start < $1.start }
        guard !sorted.isEmpty else { return [] }
        var runs: [Run] = []
        var cursor = window.lowerBound
        for segment in sorted {
            // Clamp to the window and to the previous run so overlaps
            // cannot double-count time.
            let start = max(segment.start, cursor, window.lowerBound)
            let end = min(segment.end, window.upperBound)
            guard end > start else { continue }
            if start > cursor {
                runs.append(run(stage: nil, start: cursor, end: start, window: window, width: width))
            }
            runs.append(run(stage: segment.stage, start: start, end: end, window: window, width: width))
            cursor = end
        }
        if cursor < window.upperBound {
            runs.append(run(stage: nil, start: cursor, end: window.upperBound, window: window, width: width))
        }
        guard !runs.isEmpty else { return [] }
        // Pin the last run to end exactly at `width` so floating-point
        // drift can never leave a sliver of uncovered bar.
        var last = runs[runs.count - 1]
        last = Run(x: last.x, width: max(0, width - last.x), stage: last.stage, start: last.start, end: last.end)
        runs[runs.count - 1] = last
        return runs
    }

    private static func run(stage: SleepStage?, start: Date, end: Date,
                            window: ClosedRange<Date>, width: Double) -> Run {
        let windowSeconds = window.upperBound.timeIntervalSince(window.lowerBound)
        let x = start.timeIntervalSince(window.lowerBound) / windowSeconds * width
        let w = end.timeIntervalSince(start) / windowSeconds * width
        return Run(x: x, width: w, stage: stage, start: start, end: end)
    }
}
