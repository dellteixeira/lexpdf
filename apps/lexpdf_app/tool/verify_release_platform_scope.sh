#!/usr/bin/env bash
set -euo pipefail
app_root=$(cd "$(dirname "$0")/.." && pwd)
repo_root=$(cd "$app_root/../.." && pwd)
for forbidden in ios macos; do
  if [ -d "$app_root/$forbidden" ]; then
    echo "Unsupported release platform directory found: $forbidden" >&2
    exit 1
  fi
done
if grep -REni --include='*.yml' --include='*.yaml'   'runs-on:[[:space:]]*macos|flutter[[:space:]]+build[[:space:]]+(ios|macos)'   "$repo_root/.github/workflows"; then
  echo 'Release workflows must target Android and Windows only.' >&2
  exit 1
fi
grep -q '^  android-release:' "$repo_root/.github/workflows/release-hardening.yml"
grep -q '^  windows-release:' "$repo_root/.github/workflows/release-hardening.yml"
grep -q '^  android-signed:' "$repo_root/.github/workflows/beta-distribution.yml"
grep -q '^  windows-installer:' "$repo_root/.github/workflows/beta-distribution.yml"
echo 'LexPDF release platform scope OK: Android + Windows only.'
