# ADR 0002 — Native file picker

## Status
Accepted for the first reader milestone.

## Decision
Use Flutter's `file_selector` plugin for user-driven file selection on Android, Windows and macOS.

## Rationale
The app must open local files through the platform-native graphical interface. `file_selector` is maintained by flutter.dev and provides native file selection across the target platforms.

## Security
The app only accesses files explicitly selected or authorized by the user. Cloud providers remain separate adapters.
