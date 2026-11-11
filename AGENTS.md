# Patchnap contributor rules

Read PRODUCT.md, README.md, and docs/architecture.md before changing updater behavior.

- Never execute remote shell snippets or accept arbitrary commands in the privileged component.
- Do not quit running apps, install beta channels, upgrade macOS, or silently acquire new apps.
- Keep installation authority narrow. Never grant passwordless general-purpose shell or package-manager access.
- Each provider reports discovery, eligibility, installation, and version verification separately.
- Recheck power, user activity, app activity, and exclusions immediately before each install.
- Automated tests use fixtures; never update the developer's apps as a test side effect.
- Clearly label unsupported coverage and release limitations.
- Keep brand decisions in DESIGN.md after the owner chooses the direction.
