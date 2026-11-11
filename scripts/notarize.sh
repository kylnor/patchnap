#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 2 ]] || { echo 'Usage: scripts/notarize.sh <zip> <keychain-profile>' >&2; exit 64; }
xcrun notarytool submit "$1" --keychain-profile "$2" --wait
xcrun stapler staple dist/Patchnap.app
xcrun stapler validate dist/Patchnap.app
spctl --assess --type execute --verbose=2 dist/Patchnap.app
ditto -c -k --sequesterRsrc --keepParent dist/Patchnap.app "$1"
shasum -a 256 "$1" > "$1.sha256"
