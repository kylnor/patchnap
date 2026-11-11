# Patchnap

Patchnap is a free, open-source macOS utility that checks for stable application updates and installs eligible updates while the computer is idle and on power.

Kyle chose the name Patchnap on November 11, 2026. Working line: “Updates handled. Go get some sleep.” The intended personality is friendly, playful, and dependable, with a sleepy little patch mascot. patchnap.com returned unregistered at the initial Verisign RDAP check on November 11, 2026, then registered at the final check. Ownership and DNS are not confirmed. No trademark clearance has been performed.

## People and promise

For Mac users tired of manually opening updaters every day. The primary job is to complete update chores with visible, honest coverage. The main action is enabling background maintenance once; day to day, a menu bar status and history should suffice.

## Required behavior

- Discover installed apps and distinguish supported, excluded, and unsupported apps.
- Check every few hours; favor overnight maintenance with idle catch-up.
- Install only when on power and idle; never quit or kill an app to update it.
- Stable releases only, with explicit per-app exclusion and version holds.
- Do not install a new app as a side effect of scanning.
- Route App Store updates through an existing signed-in Apple Account, with scoped installation authority.
- Verify resulting installed versions. A successful process exit alone is not a verified update.
- Persist outcomes and retry with bounded backoff; surface authentication and manual actions without repeated prompts.
- Preserve system sleep. No promise of running while a sleeping or powered-off Mac cannot execute.
- No telemetry, account, subscription, or hosted backend.

## Delivery

Native SwiftUI menu bar app, a command-line/agent engine, explicit background registration, and a public GitHub repository with an OSI-approved license. Downloadable builds must distinguish unsigned development artifacts from signed and notarized releases. Public release claims must match actual tested providers.

## Product truth

The capabilities above are the implementation target, not claims that they already work. Current implementation and acceptance evidence belong in README.md and docs/acceptance.md.
