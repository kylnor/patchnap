# Acceptance evidence

## Verified so far — November 11, 2026

- Native Swift package compiled on Apple Silicon with Apple Swift 6.4.2 and a macOS 14 minimum deployment target.
- 30 Swift Testing test functions passed across three suites, including parameterized stable/preview labels, power/idle/running-app fail-closed policy, exclusions and holds, bounded retry delays, corrupt-settings refusal, persistence round trips, overlapping-run refusal, cask artifact restrictions, JSON streams, and untrusted token rejection.
- The real installed Homebrew cask metadata shape was inspected read-only. No applications were upgraded during testing.

## Required before claiming complete live acceptance

- Background registration, pause, wake catch-up, and removal on a real Mac.
- App Store helper installation, root ownership/integrity checks, correct-user enforcement, and removal.
- One consented closed-app update per provider, followed by independent version and signature verification.
- App running, battery power, user returns, excluded app, held version, failed download, and authentication-needed cases.

These pending checks are not waived by unit tests or by CI packaging.

## Current native review

An independent fresh review returned `ship` for the captured desktop light overview, light app list and minimum-size dark settings window. It found no material visual fixes. The named reviewer package was unavailable; a fresh reviewer used the installed generated Impeccable reviewer specification. External quality-card screenshots were unavailable. This is a bounded native visual review, not a security audit or proof of unattended installation.

The standalone adapter additionally passed fixture tests for catalog ambiguity, stable HTTPS checksummed downloads, architecture/macOS metadata, known SHA-256 content, refusal of archive traversal, and restoration of an actual temporary directory after failed replacement verification. No real user application was updated by these tests.

## Initial 0.1.0 release packaging verified

- Final native SwiftUI app and three executables built on Apple Silicon.
- The release bundle passed `codesign --verify --deep --strict`.
- Apple notarization accepted submission `c6b8a357-51cf-4244-887f-ac9f31acfdc7`; stapling and ticket validation passed, and Gatekeeper reported `accepted`, `source=Notarized Developer ID`.
- The packaged App Store binary's JSON output was checked directly; a bundled-agent read-only discovery pass was run separately from unit tests.
- Real inventory checks included App Store apps, installed Homebrew casks, catalog-matched standalone apps and unsupported apps. No real application upgrade was performed.

The downloadable build is an Apple Silicon prerelease. Intel Macs can build the source, but an Intel binary and physical Intel acceptance have not been verified.
