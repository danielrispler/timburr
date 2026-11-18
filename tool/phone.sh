#!/usr/bin/env bash
# Build the release APK with the Supabase config baked in, check it, install it on the phone.
# `adb install -r` keeps the phone's local data; `flutter install` would wipe it.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APK=build/app/outputs/flutter-apk/app-release.apk
ADB="${ADB:-$HOME/Library/Android/sdk/platform-tools/adb}"

# A build without .env.json has no Supabase URL, so sync is silently off.
# Grep the project host: the Supabase library itself contains "supabase.co".
check_config() {
  local host hits
  host="$(python3 -I -c 'import json,sys,urllib.parse as u; print(u.urlparse(json.load(open(".env.json"))["SUPABASE_URL"]).hostname)')"
  hits="$(unzip -p "$APK" lib/arm64-v8a/libapp.so | LC_ALL=C grep -a -c "$host" || true)"
  if [ "${hits:-0}" -le 0 ]; then
    echo "FAIL: $APK does not contain the Supabase project host; sync would be off." >&2
    return 1
  fi
  echo "ok: Supabase project host found in the APK ($hits hits)"
}

if [ "${1:-}" != "--check-only" ]; then
  cd "$ROOT"
  flutter build apk --dart-define-from-file=.env.json
  check_config
  "$ADB" install -r "$APK"
else
  cd "$ROOT"
  check_config
fi
