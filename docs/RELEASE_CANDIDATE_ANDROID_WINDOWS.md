# LexPDF Release Candidate — Android + Windows

LexPDF release candidates are produced only for **Android** and **Windows**.

## Android

- target SDK 36;
- signed APKs per ABI;
- signed Android App Bundle;
- ARM64 artifact validation;
- compiled target-SDK inspection;
- SHA-256 checksums and release manifest.

## Windows

- x64 release bundle;
- Inno Setup installer;
- optional Authenticode signing when credentials are configured;
- SHA-256 checksums and release manifest;
- native Windows PDF rendering contracts remain release-blocking.

## Release gate

A release candidate advances only when Flutter analyze/tests, Android and Windows release builds, smoke checks, stable lockfiles, backend security invariants and artifact manifests all pass.

The Render Core visual hardware matrix remains a separate physical acceptance gate; CI cannot certify perceived display sharpness.
