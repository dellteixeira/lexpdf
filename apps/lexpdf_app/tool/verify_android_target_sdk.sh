#!/usr/bin/env bash
set -euo pipefail

minimum_target_sdk="${MINIMUM_TARGET_SDK:-36}"
report_path="${ANDROID_TARGET_SDK_REPORT:-ANDROID_TARGET_SDK.txt}"

if [ "$#" -lt 1 ]; then
  echo "Usage: $0 <apk> [<apk> ...]" >&2
  exit 2
fi

sdk_root="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
if [ -z "$sdk_root" ] || [ ! -d "$sdk_root/build-tools" ]; then
  echo "Android SDK build-tools directory was not found." >&2
  exit 1
fi

aapt_path=$(find "$sdk_root/build-tools" -maxdepth 2 -type f \( -name aapt -o -name aapt2 \) -print | sort -V | tail -n 1)
if [ -z "$aapt_path" ] || [ ! -x "$aapt_path" ]; then
  echo "aapt/aapt2 was not found in Android SDK build-tools." >&2
  exit 1
fi

: > "$report_path"
for apk in "$@"; do
  if [ ! -s "$apk" ]; then
    echo "APK not found or empty: $apk" >&2
    exit 1
  fi

  if [[ "$(basename "$aapt_path")" == "aapt2" ]]; then
    badging=$("$aapt_path" dump badging "$apk")
  else
    badging=$("$aapt_path" dump badging "$apk")
  fi

  target=$(printf '%s\n' "$badging" | sed -n "s/^targetSdkVersion:'\([0-9][0-9]*\)'.*/\1/p" | head -n 1)
  sdk=$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([0-9][0-9]*\)'.*/\1/p" | head -n 1)
  package=$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)

  if [ -z "$target" ]; then
    echo "Could not read targetSdkVersion from $apk" >&2
    exit 1
  fi
  if [ "$target" -lt "$minimum_target_sdk" ]; then
    echo "APK $apk targets API $target; minimum required is API $minimum_target_sdk." >&2
    exit 1
  fi

  printf '%s package=%s minSdk=%s targetSdk=%s requiredTargetSdk>=%s\n' \
    "$(basename "$apk")" "${package:-unknown}" "${sdk:-unknown}" "$target" "$minimum_target_sdk" \
    | tee -a "$report_path"
done
