# Contributing

Issues, reproducible bug reports, accessibility improvements, and provider fixtures are welcome. Keep changes focused and do not broaden installation authority to make a test pass.

1. Read PRODUCT.md and docs/architecture.md.
2. Run `swift test` on a Mac with Swift 6 or newer.
3. Run `scripts/build-app.sh` and verify the menu bar app locally.
4. For provider changes, use recorded public metadata and temporary fake bundles. No test should install, remove, quit, or upgrade a user's real app.
5. Explain supported coverage and include evidence of both successful updates and safe deferral.

The native app uses standard SwiftUI controls and semantic colors for accessibility. Once a brand direction is approved, DESIGN.md is the visual source of truth. Original mascot vectors are included under the repository's MIT license; please do not imply an unofficial fork is an official release.
