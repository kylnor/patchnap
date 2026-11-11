#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 2 ]] || { echo 'Usage: scripts/notarize.sh <zip> <keychain-profile>' >&2; exit 64; }
xcrun notarytool submit "$1" --keychain-profile "$2" --wait
xcrun stapler staple dist/Patchnap.app
xcrun stapler validate dist/Patchnap.app
spctl --assess --type execute --verbose=2 dist/Patchnap.app
ditto -c -k --sequesterRsrc --keepParent dist/Patchnap.app "$1"
patchnap_archive_dir=$(dirname "$1")
patchnap_archive_name=$(basename "$1")
(cd "$patchnap_archive_dir" && shasum -a 256 "$patchnap_archive_name" > "$patchnap_archive_name.sha256")
