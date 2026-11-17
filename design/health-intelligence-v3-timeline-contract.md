# Health Intelligence V3 — Timeline design and implementation contract

Status: GPT-authored design contract, **not implemented**, independent of Draft PR #4 sleep page.
Baseline main: `5468011281f46c897e8315245fb4a56a9a15be47`.
Owner: GPT (visual and critical code); Muse (Mac build, screenshots, hardware/CI evidence).
Scope: iPhone P1/P2 after stable P0; watchOS P5. No changes to health data or signing.

## Product objective
A chronological, explainable, privacy-first account of a day, not a wellness score masquerading as a diagnosis. User can identify **what happened, when, from which source, and whether it is reliable**. Do not copy Bevel's graphics or copy.

## Information architecture
- Entry: Home > Today timeline preview; tap "View all" to open full Timeline.
- Preview: header "今日记录", local date, latest three eligible events, "查看全部".
- Full page: date selector, filter chips (全部 / 睡眠 / 运动 / 体征 / 手动), vertical chronological event list, explicit source detail sheet.
- Order: newest first within a date; sleep event anchored at end time, showing full start–end range; date grouping uses device-local timezone and recomputes on timezone change.
- No inferred medical events; no placeholder metrics presented as real.

## Visual system
Use existing V3 semantic design tokens; do not introduce a competing hard-coded palette.
- Content inset 20pt (compact width), 24pt (regular); vertical rhythm 8/12/16/24pt.
- Timeline: time gutter 48pt minimum, rail 2pt, marker 8pt; content card min height 64pt; marker centered on first title baseline.
- Text: title body semibold, value title3 semibold, source and timestamp caption; respect Dynamic Type without fixed text height.
- Avoid relying on color alone: icon + explicit type label. Light/dark foreground text contrast >=4.5:1 for normal text, 3:1 for large text and essential non-text indicators.
- Card order: event title, principal value (with unit), capture interval, provenance (device/app), freshness/error disclosure. Long labels wrap rather than truncate values.
- Reduce Motion: no position/scale entrance animations; VoiceOver event combines type, time, value/unit, provenance, and action; filter chips have selected state and meaningful labels.
- Charts: never interpolate missing measurements into a continuous line. A missing interval is visually empty, not "normal" or "awake".

## Typed data and provenance
Proposed UI-facing model (contract, not committed Swift code):
```swift
struct TimelineEvent: Identifiable {
    let id: String              // stable namespaced source + source record id
    let kind: Kind               // sleep, workout, vital, manual
    let start: Date
    let end: Date
    let title: String
    let value: Decimal?
    let unit: String?
    let sourceName: String
    let sourceDevice: String?
    let recordedAt: Date?
    let quality: Quality         // measured, userEntered, derived
}
```
Sort by `end` descending, tie-break `start` then `id` for determinism. Deduplicate only identical stable IDs; retain distinct devices unless source records are proven equivalent. Derivations must disclose formula/source. No event may be created from absence of data.

## Independent states
Loading: accessible progress label and non-numeric skeleton.
Loaded: events with explicit local times and source.
Empty: "这一天暂无记录" plus optional data-source help, not a health judgment.
Not authorized / unavailable: explain permission or unsupported metric without inferring a denial from an empty HealthKit query.
Read failure: independent retry action; never collapse into Empty.
Partial failure: show successfully loaded events plus unobtrusive error summary; indicate affected categories.
Stale: show last observed time; no implied live reading.

## Security and scope
Read HealthKit only with needed entitlement and user permission. On-device first. Do not put health values, identifiers, P12, provisioning, UDID or passwords in CI logs, issues or screenshots. Demo fixtures must be synthetic and labeled.

## Acceptance matrix
1. Light/dark x loaded/empty/error/partial, 8 screenshots; plus largest supported Dynamic Type and VoiceOver traversal.
2. Cross-midnight sleep (22:30–06:40) grouped without clipping, proper start/end display.
3. Missing 30-minute interval remains a gap; 50 short segments never overflow.
4. Two sources same timestamp are not silently collapsed; repeated identical source ID deduplicates.
5. Timezone change and daylight-saving transition preserve absolute instants, update local grouping.
6. One category fails while another succeeds => partial state; all fail => error; empty success => empty.
7. Provenance/source detail visible; no fabricated values; no upload.
8. Scroll performance and memory measured on target iPhone before release; screenshots/CI are not device proof.

## Rollout and rollback
Design contract only; no source file overlap with `v3/sleep-page`. After PR #4 B1/B2 are fixed and reviewed, implement on a new feature branch, one vertical slice at a time (synthetic fixture preview -> read-only adapter -> accessibility -> real device). Require PR head SHA, workflow run ID, screenshot artifact, test matrix and precise rollback commit. Revert only the feature branch change if regression occurs; preserve iPhone P0 baseline. No merge without explicit authorization.

## Priority queue
P0: Resolve PR #4 timeline geometry and independent sleep read states; verify iPhone signing delivery.
P1: Complete seven-screen visual acceptance and shared tokens.
P2: Implement Timeline read-only, then trend charts with provenance and missing-data semantics.
P3: Personal health reports with explainable, non-diagnostic language.
P5: Watch implementation and independent hardware QA.
