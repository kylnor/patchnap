#!/bin/bash
# Run on macOS with Xcode Command Line Tools. No package installation occurs here.
set -euo pipefail
cd "$(dirname "$0")/.."
patchnap_arch=${PATCHNAP_ARCH:-$(uname -m)}
patchnap_mas=${PATCHNAP_MAS_BINARY:-}
if [[ -z $patchnap_mas ]]; then
  for patchnap_candidate in /opt/homebrew/opt/mas/libexec/bin/mas /usr/local/opt/mas/libexec/bin/mas; do
    if [[ -x $patchnap_candidate ]]; then patchnap_mas=$patchnap_candidate; break; fi
  done
fi
scripts/make-icon.sh
swift build -c release --arch "$patchnap_arch"
patchnap_bin=$(swift build -c release --arch "$patchnap_arch" --show-bin-path)
patchnap_app="$PWD/dist/Patchnap.app"
rm -rf "$patchnap_app"
mkdir -p "$patchnap_app/Contents/MacOS" "$patchnap_app/Contents/Resources" "$patchnap_app/Contents/Library/LaunchAgents"
cp "$patchnap_bin/Patchnap" "$patchnap_bin/patchnap-agent" "$patchnap_bin/patchnap-store-helper" "$patchnap_app/Contents/MacOS/"
cp Resources/Info.plist "$patchnap_app/Contents/Info.plist"
cp Resources/com.patchnap.agent.plist "$patchnap_app/Contents/Library/LaunchAgents/"
cp scripts/install-store-helper.sh scripts/remove-store-helper.sh "$patchnap_app/Contents/Resources/"
cp LICENSE THIRD_PARTY_NOTICES.md "$patchnap_app/Contents/Resources/"
if [[ -f Resources/Patchnap.icns ]]; then cp Resources/Patchnap.icns "$patchnap_app/Contents/Resources/"; fi
if [[ -n $patchnap_mas ]]; then
  [[ -x $patchnap_mas ]] || { echo 'PATCHNAP_MAS_BINARY must name an executable.' >&2; exit 1; }
  file "$patchnap_mas" | grep -q 'Mach-O' || { echo 'Supply the mas Mach-O binary, not its shell wrapper.' >&2; exit 1; }
  cp "$patchnap_mas" "$patchnap_app/Contents/Resources/mas"
  patchnap_mas_license=${PATCHNAP_MAS_LICENSE:-$(dirname "$(dirname "$(dirname "$patchnap_mas")")")/LICENSE}
  [[ -f $patchnap_mas_license ]] || { echo 'Supply PATCHNAP_MAS_LICENSE when bundling mas.' >&2; exit 1; }
  cp "$patchnap_mas_license" "$patchnap_app/Contents/Resources/mas-LICENSE"
  cp THIRD_PARTY_NOTICES.md "$patchnap_app/Contents/Resources/mas-NOTICES"
  "$patchnap_mas" version > "$patchnap_app/Contents/Resources/mas.version"
  [[ $(cat "$patchnap_app/Contents/Resources/mas.version") == '7.0.0' ]] || { echo 'This release carries notices for mas 7.0.0. Update the audited version and notices before bundling another version.' >&2; exit 1; }
  cp -R Resources/ThirdParty "$patchnap_app/Contents/Resources/"
fi
if [[ -n ${PATCHNAP_SIGN_IDENTITY:-} ]]; then
  [[ ${PATCHNAP_TEAM_ID:-} =~ ^[A-Z0-9]{10}$ ]] || { echo 'Set PATCHNAP_TEAM_ID for the signing identity.' >&2; exit 1; }
  sed -i '' "s/__PATCHNAP_TEAM_ID__/$PATCHNAP_TEAM_ID/g" "$patchnap_app/Contents/Resources/install-store-helper.sh"
  patchnap_identity=$PATCHNAP_SIGN_IDENTITY
  patchnap_sign_flags=(--options runtime --timestamp)
else
  patchnap_identity=-
  patchnap_sign_flags=(--timestamp=none)
fi
for patchnap_binary in "$patchnap_app/Contents/MacOS/"* "$patchnap_app/Contents/Resources/mas"; do
  if [[ -f $patchnap_binary ]]; then codesign --force --sign "$patchnap_identity" "${patchnap_sign_flags[@]}" "$patchnap_binary"; fi
done
codesign --force --sign "$patchnap_identity" "${patchnap_sign_flags[@]}" "$patchnap_app"
codesign --verify --deep --strict "$patchnap_app"
patchnap_zip="$PWD/dist/Patchnap-0.1.0-$patchnap_arch.zip"
ditto -c -k --sequesterRsrc --keepParent "$patchnap_app" "$patchnap_zip"
(cd dist && shasum -a 256 "$(basename "$patchnap_zip")" > "$(basename "$patchnap_zip").sha256")
printf '%s\n' "$patchnap_zip"
