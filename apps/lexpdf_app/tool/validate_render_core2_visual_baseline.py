#!/usr/bin/env python3
"""Validate the LexPDF Render Core 2 Phase 1 visual-baseline gate.

The validator intentionally fails while evidence is incomplete. It does not judge
image quality automatically; it verifies that the required physical-test matrix
and environment record exist before Phase 2 may begin.
"""

from __future__ import annotations

import json
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parent
MANIFEST = ROOT / "render_core2_visual_baseline.json"
REQUIRED_ZOOMS = {75, 100, 125, 200, 300, 400}
REQUIRED_INTERACTIONS = {
    "pan_200",
    "pan_400",
    "resize_100",
    "maximize_restore_maximize_100",
    "zoom_75_200_400_100",
}
REQUIRED_ENVIRONMENT = {
    "windows_edition",
    "windows_version",
    "windows_build",
    "display_resolution",
    "display_scaling_percent",
    "lexpdf_version",
    "reference_reader",
    "reference_reader_version",
    "window_maximized",
}
FINAL_STATUSES = {"pass", "fail", "observed"}


def nonempty(value: object) -> bool:
    if value is None:
        return False
    if isinstance(value, str):
        return bool(value.strip())
    return True


def main() -> int:
    errors: list[str] = []

    if not MANIFEST.is_file():
        print(f"ERROR: baseline manifest missing: {MANIFEST}", file=sys.stderr)
        return 2

    data = json.loads(MANIFEST.read_text(encoding="utf-8"))

    if data.get("phase") != 1:
        errors.append("manifest phase must be 1")

    environment = data.get("environment") or {}
    for key in sorted(REQUIRED_ENVIRONMENT):
        if not nonempty(environment.get(key)):
            errors.append(f"environment.{key} is pending")

    rows = data.get("zoom_matrix") or []
    by_zoom = {row.get("zoom_percent"): row for row in rows}
    missing_zooms = REQUIRED_ZOOMS - set(by_zoom)
    if missing_zooms:
        errors.append(f"missing zoom rows: {sorted(missing_zooms)}")

    for zoom in sorted(REQUIRED_ZOOMS):
        row = by_zoom.get(zoom)
        if row is None:
            continue
        for side in ("lexpdf", "reference"):
            status = row.get(f"{side}_status")
            if status not in FINAL_STATUSES:
                errors.append(f"zoom {zoom}: {side}_status is pending/invalid")
            if not nonempty(row.get(f"{side}_observation")):
                errors.append(f"zoom {zoom}: {side}_observation is missing")
            if not nonempty(row.get(f"{side}_evidence")):
                errors.append(f"zoom {zoom}: {side}_evidence is missing")

    interactions = data.get("interaction_matrix") or []
    by_case = {row.get("case"): row for row in interactions}
    missing_cases = REQUIRED_INTERACTIONS - set(by_case)
    if missing_cases:
        errors.append(f"missing interaction cases: {sorted(missing_cases)}")

    for case in sorted(REQUIRED_INTERACTIONS):
        row = by_case.get(case)
        if row is None:
            continue
        if row.get("status") not in FINAL_STATUSES:
            errors.append(f"interaction {case}: status is pending/invalid")
        if not nonempty(row.get("observation")):
            errors.append(f"interaction {case}: observation is missing")
        if not nonempty(row.get("evidence")):
            errors.append(f"interaction {case}: evidence is missing")

    if data.get("phase_1_approved") is not True:
        errors.append("phase_1_approved is not true")

    if errors:
        print("Render Core 2 Phase 1 gate: BLOCKED")
        for error in errors:
            print(f"- {error}")
        print("\nDo not begin Phase 2 until this command exits successfully.")
        return 1

    print("Render Core 2 Phase 1 gate: PASS")
    print("The physical visual baseline is complete and Phase 2 may begin.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
