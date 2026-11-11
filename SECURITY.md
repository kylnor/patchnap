# Security policy

Please report vulnerabilities privately through GitHub's “Report a vulnerability” action on this repository. Do not include credentials or a full personal app inventory in a public issue.

The installation helper is a privilege boundary. Changes that broaden accepted arguments, trust user-writable executables, skip installed-app validation, or add arbitrary shell execution are unacceptable. The helper only updates existing Mac App Store apps. Homebrew always runs without root authority.

Patchnap is early alpha software. Signed/notarized distribution and a fixture-tested policy do not replace live acceptance or prove that every provider behaves safely on every macOS release. Current limits and verification evidence belong in docs/acceptance.md.
