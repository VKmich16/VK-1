#!/bin/bash
# Offline checks use their own profile and never read the user's DSH credentials.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
BIN="$ROOT/dist/DSH大肥鱼桌宠.app/Contents/MacOS/DSHBalancePet"
OUT="$ROOT/build/verification"
mkdir -p "$OUT"
TEST_PROFILE="$(mktemp -d "$OUT/profile.XXXXXX")"
export DSHPET_HOME="$TEST_PROFILE"
export DSHPET_OFFLINE=1
PET_PID=""
DUPLICATE_PID=""
cleanup() {
  if [[ -n "$DUPLICATE_PID" ]]; then
    kill "$DUPLICATE_PID" 2>/dev/null || true
    wait "$DUPLICATE_PID" 2>/dev/null || true
  fi
  if [[ -n "$PET_PID" ]]; then
    kill "$PET_PID" 2>/dev/null || true
    wait "$PET_PID" 2>/dev/null || true
  fi
  rm -rf "$TEST_PROFILE"
}
trap cleanup EXIT

"$BIN" --selftest | tee "$OUT/selftest.txt"
"$BIN" --snapshot "$OUT/snapshots"
codesign --verify --strict "$ROOT/dist/DSH大肥鱼桌宠.app"
[[ "$(shasum -a 256 "$ROOT/Resources/sprite.png" | cut -d ' ' -f 1)" == a98329d36dd9169a1856f3a396bc9e602ed1a739bd3097eead1b744c6bb3dd71 ]]
[[ "$(shasum -a 256 "$ROOT/Resources/sprite-gpt.png" | cut -d ' ' -f 1)" == 41f79346666fbb776ee2baef2a0cf044850a50e30c177b3adf9bb14e84296467 ]]
[[ "$(shasum -a 256 "$ROOT/Resources/sprite-claude.png" | cut -d ' ' -f 1)" == 81f0e787057dd9d5e400e5f43a44a1b55da4adfa7329aa712d986531cbd5d90d ]]
[[ "$(shasum -a 256 "$ROOT/Resources/sprite-gemini.png" | cut -d ' ' -f 1)" == ad5fbeb07c2212476d4670ec56b8e7202e21f05b42ab0461cf3150a43f91a2ef ]]
[[ "$(shasum -a 256 "$ROOT/Resources/sprite-deepseek-offline.png" | cut -d ' ' -f 1)" == fb4c5cb3001ca43d268d2e3bdf39b9d984e28d592e3b73e46e6fd44ccebb4555 ]]
cmp "$ROOT/Resources/hit.mp3" "$ROOT/../原版（Windows版）/DSH余额桌宠/hit.mp3"
for resource in sprite.png sprite-gpt.png sprite-claude.png sprite-gemini.png sprite-deepseek-offline.png hit.mp3; do
  cmp "$ROOT/Resources/$resource" "$ROOT/dist/DSH大肥鱼桌宠.app/Contents/Resources/$resource"
done

"$BIN" > "$TEST_PROFILE/app.log" 2>&1 &
PET_PID=$!
for attempt in {1..50}; do
  [[ -f "$TEST_PROFILE/status.json" ]] && break
  sleep 0.1
done
"$BIN" --windows > "$OUT/window-status.txt"
kill -0 "$PET_PID"
[[ "$(plutil -extract character raw "$TEST_PROFILE/status.json")" == deepseek ]]
"$BIN" > "$TEST_PROFILE/duplicate.log" 2>&1 &
DUPLICATE_PID=$!
for attempt in {1..30}; do
  kill -0 "$DUPLICATE_PID" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "$DUPLICATE_PID" 2>/dev/null; then
  echo 'FAIL: duplicate instance is still running' >&2
  exit 1
fi
if wait "$DUPLICATE_PID"; then
  echo 'FAIL: a duplicate instance was allowed' >&2
  exit 1
fi
DUPLICATE_PID=""
if "$BIN" --reset > "$TEST_PROFILE/reset.log" 2>&1; then
  echo 'FAIL: reset should reject a running profile' >&2
  exit 1
fi
kill "$PET_PID"
wait "$PET_PID" 2>/dev/null || true
PET_PID=""
printf '%s\n' '{"sizeIndex":2,"soundOn":false,"snapOnRelease":false,"pollSeconds":60,"character":"gemini","originX":12,"originY":34}' > "$TEST_PROFILE/state.json"
"$BIN" --reset
[[ "$(plutil -extract sizeIndex raw "$TEST_PROFILE/state.json")" == 2 ]]
[[ "$(plutil -extract soundOn raw "$TEST_PROFILE/state.json")" == false ]]
[[ "$(plutil -extract pollSeconds raw "$TEST_PROFILE/state.json")" == 60 ]]
[[ "$(plutil -extract character raw "$TEST_PROFILE/state.json")" == gemini ]]
if plutil -extract originX raw "$TEST_PROFILE/state.json" >/dev/null 2>&1; then
  echo 'FAIL: reset left a saved origin' >&2
  exit 1
fi
for character in deepseek gpt claude gemini; do
  printf '{"sizeIndex":2,"soundOn":false,"pollSeconds":60,"character":"%s"}\n' "$character" > "$TEST_PROFILE/state.json"
  rm -f "$TEST_PROFILE/status.json"
  "$BIN" > "$TEST_PROFILE/app-$character.log" 2>&1 &
  PET_PID=$!
  for attempt in {1..50}; do
    [[ -f "$TEST_PROFILE/status.json" ]] && break
    sleep 0.1
  done
  "$BIN" --windows > "$OUT/window-status-$character.txt"
  kill -0 "$PET_PID"
  [[ "$(plutil -extract character raw "$TEST_PROFILE/status.json")" == "$character" ]]
  case "$character" in
    deepseek) expected_name='蓝色大肥鱼' ;;
    gpt) expected_name='GPT龙娘' ;;
    claude) expected_name='大小姐Claude' ;;
    gemini) expected_name='北美猫娘Gemini' ;;
  esac
  [[ "$(plutil -extract characterName raw "$TEST_PROFILE/status.json")" == "$expected_name" ]]
  kill "$PET_PID"
  wait "$PET_PID" 2>/dev/null || true
  PET_PID=""
done
echo 'PASS: four-character bundle, original audio, saved-character startup, duplicate prevention, and position-only reset'
