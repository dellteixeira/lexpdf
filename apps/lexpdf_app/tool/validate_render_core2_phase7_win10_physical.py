#!/usr/bin/env python3
import json
import sys
from pathlib import Path

EVIDENCE = Path(__file__).with_name('render_core2_phase7_win10_physical.json')
REQUIRED_ZOOMS = {'75', '100', '125', '200', '300', '400'}
REQUIRED_INTERACTIONS = {
    'pan_200',
    'pan_400',
    'resize_100',
    'maximize_restore_maximize_100',
    'zoom_75_200_400_100',
    'page_navigation',
}


def fail(message: str) -> None:
    print(f'Render Core 2 Phase 7 gate: BLOCKED — {message}')
    raise SystemExit(1)


def main() -> None:
    if not EVIDENCE.exists():
        fail(f'missing evidence file: {EVIDENCE}')

    data = json.loads(EVIDENCE.read_text(encoding='utf-8'))
    if data.get('phase') != 7:
        fail('evidence phase must be 7')
    if data.get('approved') is not True:
        fail('physical approval is still false')
    if not data.get('reference_application'):
        fail('reference_application is required')

    env = data.get('environment') or {}
    for key in (
        'windows_version',
        'display_scaling_percent',
        'device_pixel_ratio',
        'gpu',
        'display_resolution',
    ):
        if env.get(key) in (None, ''):
            fail(f'environment.{key} is required')

    matrix = data.get('zoom_matrix') or {}
    if set(matrix) != REQUIRED_ZOOMS:
        fail(f'zoom matrix must contain exactly {sorted(REQUIRED_ZOOMS)}')

    for zoom in sorted(REQUIRED_ZOOMS, key=int):
        entry = matrix[zoom]
        if entry.get('status') != 'pass':
            fail(f'{zoom}% is not PASS')
        if not entry.get('requested_px') or not entry.get('returned_px'):
            fail(f'{zoom}% is missing requested/returned pixel dimensions')
        if entry.get('requested_px') != entry.get('returned_px'):
            fail(f'{zoom}% requested and returned physical pixels differ')
        if not entry.get('lexpdf_evidence') or not entry.get('reference_evidence'):
            fail(f'{zoom}% is missing LexPDF/reference physical evidence')

    interactions = data.get('interactions') or {}
    if set(interactions) != REQUIRED_INTERACTIONS:
        fail('interaction evidence set is incomplete')
    for name, status in interactions.items():
        if status != 'pass':
            fail(f'interaction {name} is not PASS')

    print('Render Core 2 Phase 7 gate: PASS')


if __name__ == '__main__':
    main()
