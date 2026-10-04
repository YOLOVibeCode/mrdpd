#!/usr/bin/env bash
# `just ipad-sim-check`: the iPad app in an iPad Pro 13" simulator against a real mrdpd-host on
# loopback, input logged but never posted (--no-inject). Checks the host received the clicks and
# keys the UI test produced, and that the Ctrl+Option switch keys stayed on the iPad.
set -euo pipefail
cd "$(dirname "$0")/.."

work=$(mktemp -d)
port=3398
export MRDPD_HOME="$work/home"
cleanup() {
    [[ -n "${host_pid:-}" ]] && kill "$host_pid" 2>/dev/null || true
    rm -rf "$work"
}
trap cleanup EXIT

.build/debug/mrdpd-host serve --bind 127.0.0.1 --port "$port" --no-inject --log-input > "$work/host.log" 2>&1 &
host_pid=$!
sleep 1
.build/debug/mrdpd-host pair --bind 127.0.0.1 --port "$port" --name "sim-check" --link-file "$work/link" > /dev/null

name="mrdpd iPad Pro 13 (test)"
udid=$(xcrun simctl list devices available | awk -v n="$name" 'index($0, n) { match($0, /[0-9A-F-]{36}/); print substr($0, RSTART, RLENGTH); exit }')
if [[ -z "$udid" ]]; then
    runtime=$(xcrun simctl list runtimes available | awk '/iOS/ { match($0, /com\.apple\.CoreSimulator\.SimRuntime\.iOS-[0-9-]+/); r = substr($0, RSTART, RLENGTH) } END { print r }')
    udid=$(xcrun simctl create "$name" com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M4-8GB "$runtime")
fi
echo "simulator $udid"

TEST_RUNNER_MRDPD_UI_TEST_LINK="$(cat "$work/link")" xcodebuild test \
    -project apps/ipad/mrdpd-ipad.xcodeproj -scheme mrdpd -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath .build/ipad DEVELOPMENT_TEAM="" CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" \
    2>&1 | grep -E "Test Case|error:|\*\* TEST" || true

log="$work/host.log"
fail=0
check() {
    if grep -q -- "$2" "$log"; then echo "ok   $1"; else echo "FAIL $1"; fail=1; fi
}
check "client connected" "connected from 127.0.0.1"
check "tap reached the Mac as a left click" "button(ViewportProtocol.MouseButton.left, down: true"
check "letter a (HID 0x04) reached the Mac" "key(usage: 4, down: true)"
check "Command (HID 0xE3) reached the Mac" "key(usage: 227, down: true)"
check "drag moved the pointer" "move(ViewportProtocol.Point01"
check "long press reached the Mac as a right click" "button(ViewportProtocol.MouseButton.right, down: true"
check "Ctrl+Option+1 switched to display 1" ": display 1 "
check "Ctrl+Option+2 switched to display 2" ": display 2 "
if grep -q "key(usage: 30, down: true)\|key(usage: 31, down: true)" "$log"; then
    echo "FAIL switch digits leaked to the Mac"
    fail=1
else
    echo "ok   switch digits stayed on the iPad"
fi
exit $fail
