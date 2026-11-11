# Architecture

## Processes

Patchnap is a SwiftUI menu bar app. It registers a bundled per-user launch agent with SMAppService. The agent wakes every 15 minutes while macOS is awake, checks for updates at a configurable interval (default 3 hours), and installs eligible updates after 10 minutes of idle time on external power. It never schedules a wake or prevents normal system sleep.

PatchnapCore contains Codable models, eligibility policy, persistent state, process execution, inventory, and provider adapters. A filesystem lock prevents overlapping app/agent runs. Data lives in the user's Application Support/Patchnap directory with private permissions.

The Homebrew adapter handles installed stable casks only. Formulae, unknown channels, installer-based or privileged casks, service-removal actions, and artifacts that cannot be mapped to a real installed app are not automatically upgraded. Existing command wrappers and quit-only uninstall metadata are allowed; the no-quit setting remains enabled and open apps are deferred. Running bundles are excluded and checked again immediately before execution. Cask metadata and versions are reloaded after installation; exit code alone is insufficient.

The Mac App Store adapter uses mas. Read-only checks run as the logged-in user. Installation is available through a separately installed root-owned helper containing a root-owned, pinned mas executable. The helper accepts only `update <numeric App Store ID>`, rechecks that the app is installed with an App Store receipt and not running, and delegates to mas. A one-time administrator installation grants the current local user permission to invoke this exact helper. No arbitrary executable, path, shell fragment, environment override, or package-manager command is accepted. Missing helper authority is shown as an actionable state.

The standalone catalog adapter matches installed app names against Homebrew's maintained public cask metadata, specializing by architecture and macOS. It requires a fixed SHA-256 and HTTPS ZIP/DMG download, refuses dependencies and installer artifacts, checks the same signed developer and bundle ID, validates Gatekeeper and architecture/macOS compatibility, and stages a replacement beside the installed app. It rechecks settings, power, idle and running apps after download. Failed post-replacement verification restores the retained original. ZIP extraction uses macOS bsdtar's traversal protections. No cask recipe, uninstall action, or wrapper is executed. App Store receipts and already-managed Homebrew apps are not replaced through this adapter.

Native Sparkle feeds and Installomator recipes remain future provider extensions. Coverage must never be presented as all installed apps.

## Safety and acceptance

- Background installs start only on external power with a known idle reading and a known running-app inventory.
- All states fail closed when detection is unavailable.
- User activity is rechecked between installs. An install already in progress is allowed to finish safely.
- Only explicit installed stable identifiers are eligible. No bulk upgrade calls.
- Exclusions, version holds, and bounded retry delays are checked for each item.
- Unsupported apps remain visible with the reason.
- No test may update real user apps. Real-machine acceptance starts with discovery and dry-run plans.
- A public alpha may contain unsigned CI artifacts; a release is called signed/notarized only after verifying those results.
