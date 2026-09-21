#!/usr/bin/env bash
set -euo pipefail
app_root=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(cd "$app_root/../.." && pwd)

retired_mobile='i''os'
retired_desktop='mac''os'

for forbidden in "$retired_mobile" "$retired_desktop"; do
  if [ -d "$app_root/$forbidden" ]; then
    echo "Unsupported release platform directory found." >&2
    exit 1
  fi
done

for workflow in   "$repo_root/.github/workflows/release-hardening.yml"   "$repo_root/.github/workflows/beta-distribution.yml"; do
  if grep -Eqi "runs-on:[[:space:]]*$retired_desktop|flutter[[:space:]]+build[[:space:]]+($retired_mobile|$retired_desktop)" "$workflow"; then
    echo 'Release workflows must target Android and Windows only.' >&2
    exit 1
  fi
done

grep -q '^  android-release:' "$repo_root/.github/workflows/release-hardening.yml"
grep -q '^  windows-release:' "$repo_root/.github/workflows/release-hardening.yml"
grep -q '^  android-signed:' "$repo_root/.github/workflows/beta-distribution.yml"
grep -q '^  windows-installer:' "$repo_root/.github/workflows/beta-distribution.yml"
echo 'LexPDF release platform scope OK: Android + Windows only.'
