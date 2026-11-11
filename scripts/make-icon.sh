#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
patchnap_iconset=$(mktemp -d /tmp/patchnap-icon.XXXXXXXX)/Patchnap.iconset
mkdir -p "$patchnap_iconset"
trap 'rm -rf "$(dirname "$patchnap_iconset")"' EXIT
for patchnap_size in 16 32 128 256 512; do
  sips -z "$patchnap_size" "$patchnap_size" brand/app-icon.png --out "$patchnap_iconset/icon_${patchnap_size}x${patchnap_size}.png" >/dev/null
  patchnap_double=$((patchnap_size * 2))
  sips -z "$patchnap_double" "$patchnap_double" brand/app-icon.png --out "$patchnap_iconset/icon_${patchnap_size}x${patchnap_size}@2x.png" >/dev/null
done
iconutil -c icns "$patchnap_iconset" -o Resources/Patchnap.icns
