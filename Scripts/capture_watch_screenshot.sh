#!/bin/bash
# Captures two real screenshots of the Watch app on a watch simulator:
# the dashboard home and the sleep section, on a 42mm (or smallest
# available) device. Writes both PNGs plus watch-manifest.json into the
# output directory.
# Usage: bash Scripts/capture_watch_screenshot.sh <HealthWatch.app path> <output dir>
# Exits 0 only when both screenshots show real app content and the
# manifest exists and parses as JSON. Any failure exits non-zero:
# nothing in this script swallows a failure, and no function that can
# fail is ever called inside a command substitution (an exit there
# would only kill the subshell and the script would carry on with an
# empty PID — the false-success hole found in #38).
# Three gates prove each shot is genuine, plus two identity checks:
#   1. simctl launch exits 0 and returns a numeric PID.
#   2. Process: launching again must return the SAME pid (the first
#      instance stayed alive); a different pid means it died and a new
#      one started. Uses only simctl launch — see below on launchctl.
#   3. Readiness: the screen must show real content (brightness gate),
#      not the nearly all-black app-launch screen.
#   4. Screen change: the shot must differ from the previous screen by
#      at least 5% of pixels (diff gate). A crashed app leaves the watch
#      face (or the previous screen) up, which differs by ~0%.
#   5. Identity: the shot must be the expected device size and carry
#      the app's signature mint accent (thousands of mint pixels on a
#      rendered dashboard, zero on a loading screen).
# Deliberately NOT used: `launchctl print gui/501/<bundle>` as a
# running-state check. In run #38 it reported "not running" for both
# launches while the sleep screenshot proves the app was running and
# rendering — the check false-negatives in this environment, so it
# cannot be a hard gate. The relaunch-pid check is the process proof
# instead.
# The Watch app is independent of the iPhone app, so only the watch app
# is installed; HealthKit on the simulator returns no data, so both shots
# show the honest empty state, never manufactured readings.
set -u
APP_PATH="${1:?usage: capture_watch_screenshot.sh <HealthWatch.app path> <output dir>}"
OUT_DIR="${2:?usage: capture_watch_screenshot.sh <HealthWatch.app path> <output dir>}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
mkdir -p "$OUT_DIR"

fail() { echo "FAIL: $1"; exit 1; }

command -v python3 >/dev/null || fail "python3 is required for the screenshot readiness check"
[ -f "$APP_PATH/Info.plist" ] || fail "Watch app Info.plist is missing"
BUNDLE_ID=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP_PATH/Info.plist") \
    || fail "could not read Watch app bundle identifier"
[ -n "$BUNDLE_ID" ] || fail "Watch app bundle identifier is empty"

echo "== watch simulators =="
xcrun simctl list devices available | grep -i "Apple Watch" || true

# Prefer a 42mm (small-screen) device, then 41mm, then any watch device.
UDID=""
for SIZE in 42mm 41mm; do
    UDID=$(xcrun simctl list devices available | grep -i "$SIZE" \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
    [ -n "$UDID" ] && break
done
if [ -z "$UDID" ]; then
    UDID=$(xcrun simctl list devices available | grep -i "Apple Watch" \
        | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)
fi
if [ -z "$UDID" ]; then
    echo "== no watch simulator found, creating a 42mm one =="
    DEVTYPE=$(xcrun simctl list devicetypes | grep -i "Apple Watch" | grep -i "42mm" \
        | head -1 | sed -E 's/^[[:space:]]*//; s/ \(com\.apple.*//')
    RUNTIME=$(xcrun simctl list runtimes | grep -i "watchOS" | tail -1 \
        | sed -E 's/^[[:space:]]*([A-Za-z]+ [0-9.]+).*/\1/')
    [ -n "$DEVTYPE" ] || fail "no 42mm watch device type on this runner"
    echo "device type: $DEVTYPE"
    echo "runtime: $RUNTIME"
    UDID=$(xcrun simctl create ScreenshotWatch "$DEVTYPE" "$RUNTIME") \
        || fail "simctl create failed"
    echo "created: $UDID"
fi
echo "using watch simulator: $UDID"

DEVICE_NAME=$(xcrun simctl list devices available | grep "$UDID" \
    | sed -E 's/^[[:space:]]*//; s/ \([0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}\).*//')
RUNTIME=$(xcrun simctl list devices available | grep -B 100 "$UDID" \
    | grep -iE '^[[:space:]]*-- .* --[[:space:]]*$' | tail -1 \
    | sed -E 's/^[[:space:]]*-- //; s/ --[[:space:]]*$//')
[ -n "$DEVICE_NAME" ] || DEVICE_NAME="unknown watch device"
[ -n "$RUNTIME" ] || RUNTIME="unknown runtime"
SLUG=$(printf '%s-%s' "$DEVICE_NAME" "$RUNTIME" | tr ' .' '--' | tr -d '()' | tr -s '-')
echo "device: $DEVICE_NAME"
echo "runtime: $RUNTIME"
echo "slug: $SLUG"

echo "== boot =="
xcrun simctl boot "$UDID" 2>&1 || echo "(already booted or boot skipped)"
echo "== wait for boot (bounded 120s) =="
for i in $(seq 1 60); do
    if xcrun simctl list devices available | grep "$UDID" | grep -q "(Booted)"; then
        echo "booted after ~$((i * 2))s"
        break
    fi
    sleep 2
done
xcrun simctl list devices available | grep "$UDID" | grep -q "(Booted)" \
    || fail "watch simulator did not reach Booted state within 120s"

echo "== install $APP_PATH =="
xcrun simctl install "$UDID" "$APP_PATH" || fail "install failed"

# Launches the app. Sets LAUNCH_PID. Called directly, never inside
# $(...): a fail() here must kill the script, not just a subshell.
# Process check: launching a second time must return the SAME pid.
# simctl launch on an already-running app brings it to the front and
# returns the existing process, so a different pid means the first
# instance died and a new one started — the app did not stay running.
# This uses only simctl launch itself: launchctl print gui/501/<bundle>
# is not used, because in run #38 it reported "not running" for both
# launches while the sleep screenshot proves the app was running and
# rendering (a label/domain false negative).
LAUNCH_PID=""
launch_and_verify() {
    local label="$1" extra="$2"
    echo "== launch $BUNDLE_ID ($label) =="
    local out
    if [ -n "$extra" ]; then
        out=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" "$extra" 2>&1) \
            || fail "Watch app failed to launch ($label)"
    else
        out=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1) \
            || fail "Watch app failed to launch ($label)"
    fi
    echo "$out"
    local pid
    # simctl launch prints "<bundle identifier>: <PID>", not a bare PID.
    # Accept only a positive numeric PID at the end of that output.
    if [[ "$out" =~ :[[:space:]]*([1-9][0-9]*)[[:space:]]*$ ]]; then
        pid="${BASH_REMATCH[1]}"
    else
        fail "could not parse a PID from simctl launch output ($label): $out"
    fi
    echo "launched pid: $pid"
    echo "== verify the same process is still running ($label) =="
    local out2 pid2
    if [ -n "$extra" ]; then
        out2=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" "$extra" 2>&1) \
            || fail "Watch app relaunch check failed ($label)"
    else
        out2=$(xcrun simctl launch "$UDID" "$BUNDLE_ID" 2>&1) \
            || fail "Watch app relaunch check failed ($label)"
    fi
    if [[ "$out2" =~ :[[:space:]]*([1-9][0-9]*)[[:space:]]*$ ]]; then
        pid2="${BASH_REMATCH[1]}"
    else
        fail "could not parse a PID from simctl relaunch output ($label): $out2"
    fi
    echo "relaunch pid: $pid2"
    [ "$pid2" = "$pid" ] \
        || fail "Watch app process did not stay running ($label): pid $pid became $pid2"
    LAUNCH_PID="$pid"
}

# Screenshots the screen before the app launches (the watch face).
# Later shots must differ from it, which proves the app is really in
# front instead of the face showing through after a crash. Best effort:
# if the baseline cannot be captured, the diff check is skipped and
# the other gates still apply.
BASELINE_PNG="/tmp/watch-baseline.png"
capture_baseline() {
    local attempt
    for attempt in 1 2 3; do
        if xcrun simctl io "$UDID" screenshot "$BASELINE_PNG" 2>/dev/null && [ -s "$BASELINE_PNG" ]; then
            echo "baseline captured (attempt $attempt)"
            return 0
        fi
        sleep 2
    done
    echo "WARNING: could not capture a baseline screenshot; the screen-change check will be skipped"
    BASELINE_PNG=""
}

# Expected screenshot size for the chosen device, from its name.
# 42mm Series 10/11: 374x446; 41mm: 352x430; 45mm: 396x484; 46mm: 410x502.
# Unknown sizes skip the check with a warning rather than failing.
expected_watch_size() {
    case "$DEVICE_NAME" in
        *42mm*) echo "374 446" ;;
        *41mm*) echo "352 430" ;;
        *45mm*) echo "396 484" ;;
        *46mm*) echo "410 502" ;;
        *) echo "" ;;
    esac
}

# Fails unless the screenshot is the expected device size and carries
# the app's signature mint accent (the dashboard always does; a loading
# screen carries zero mint pixels). Both are page-specific identifiers:
# brightness alone cannot prove the screen is this app.
check_shot_identity() {
    local png="$1" label="$2"
    local size
    size=$(expected_watch_size)
    if [ -n "$size" ]; then
        python3 "$SCRIPT_DIR/png_check.py" size "$png" $size \
            || fail "watch screenshot has the wrong size ($label)"
    else
        echo "WARNING: unknown device size for '$DEVICE_NAME'; size check skipped ($label)"
    fi
    python3 "$SCRIPT_DIR/png_check.py" color "$png" 32 178 150 60 100 \
        || fail "watch screenshot shows no app mint accent ($label): not the app screen"
}

# Fails unless two screenshots differ by at least 5% of pixels.
# A crashed app leaves the watch face (or the previous screen) up,
# which differs from the new screen by ~0%; a rendered app differs a lot.
check_screen_changed() {
    local before="$1" after="$2" label="$3"
    local result
    if result=$(python3 "$SCRIPT_DIR/png_check.py" diff "$before" "$after" 5.0 2>&1); then
        echo "screen changed ($label): $result"
    else
        fail "screen did not change after launch ($label): $result"
    fi
}

# Screenshots until the screen shows real app content, then saves it.
# The watchOS app-launch screen is nearly all black with a spinner;
# the rendered dashboard always carries white text and colored accents.
# Polls up to 60s and fails rather than saving a loading screen.
shoot_when_ready() {
    local final="$1" label="$2"
    local tmp="/tmp/watch-shot-$label.png"
    local attempt fraction
    for attempt in $(seq 1 20); do
        if xcrun simctl io "$UDID" screenshot "$tmp" 2>/dev/null && [ -s "$tmp" ]; then
            if fraction=$(python3 "$SCRIPT_DIR/png_check.py" bright "$tmp" 1.0 2>&1); then
                echo "ready ($label, attempt $attempt): $fraction"
                mv "$tmp" "$final"
                echo "OK: $(wc -c < "$final") bytes -> $final"
                return 0
            fi
            echo "not ready yet ($label, attempt $attempt): $fraction"
        else
            echo "screenshot attempt $attempt failed ($label), retrying"
        fi
        sleep 3
    done
    fail "Watch app screen never showed real content within 60s ($label)"
}

HOME_PNG="$OUT_DIR/watch-home-$SLUG.png"
SLEEP_PNG="$OUT_DIR/watch-sleep-$SLUG.png"

capture_baseline

launch_and_verify "home" ""
HOME_PID="$LAUNCH_PID"
shoot_when_ready "$HOME_PNG" "home"
check_shot_identity "$HOME_PNG" "home"
if [ -n "$BASELINE_PNG" ]; then
    check_screen_changed "$BASELINE_PNG" "$HOME_PNG" "home"
fi

echo "== relaunch for the sleep section =="
xcrun simctl terminate "$UDID" "$BUNDLE_ID" 2>&1 || echo "(terminate skipped)"
launch_and_verify "sleep" "-watchScreenshotSleep"
SLEEP_PID="$LAUNCH_PID"
# Let the in-app scroll to the sleep section settle before the gate runs,
# so the sleep shot cannot be the dashboard top by accident.
sleep 3
shoot_when_ready "$SLEEP_PNG" "sleep"
check_shot_identity "$SLEEP_PNG" "sleep"
# The sleep shot must differ from the home shot: this also proves the
# scroll to the sleep section actually happened.
check_screen_changed "$HOME_PNG" "$SLEEP_PNG" "sleep"

case "$HOME_PID" in ''|*[!0-9]*) fail "bad home PID: $HOME_PID" ;; esac
case "$SLEEP_PID" in ''|*[!0-9]*) fail "bad sleep PID: $SLEEP_PID" ;; esac
HOME_BYTES=$(wc -c < "$HOME_PNG")
SLEEP_BYTES=$(wc -c < "$SLEEP_PNG")
printf '{\n  "device": "%s",\n  "runtime": "%s",\n  "mode": "dark",\n  "bundleId": "%s",\n  "home": {"file": "%s", "bytes": %s, "pid": %s},\n  "sleep": {"file": "%s", "bytes": %s, "pid": %s},\n  "note": "Simulator has no HealthKit data; both shots show the honest empty state."\n}\n' \
    "$DEVICE_NAME" "$RUNTIME" "$BUNDLE_ID" \
    "$(basename "$HOME_PNG")" "$HOME_BYTES" "$HOME_PID" \
    "$(basename "$SLEEP_PNG")" "$SLEEP_BYTES" "$SLEEP_PID" \
    > "$OUT_DIR/watch-manifest.json"
python3 -m json.tool "$OUT_DIR/watch-manifest.json" > /dev/null \
    || fail "watch-manifest.json failed JSON validation"
echo "== manifest =="
cat "$OUT_DIR/watch-manifest.json"
echo "OK: watch home + sleep captured"
