#!/bin/bash
# Called with administrator authorization by the signed app. Never executes user-supplied code as root.
set -euo pipefail
if [[ $EUID != 0 || $# != 2 ]]; then
  echo 'Run with administrator authority, an app path, and a local user name.' >&2; exit 64
fi
patchnap_app=$1
patchnap_user=$2
[[ $patchnap_user =~ ^[a-z_][a-z0-9_-]*$ ]] || { echo 'Invalid local user.' >&2; exit 64; }
[[ $(/usr/bin/id -u "$patchnap_user") -ge 500 ]] || { echo 'A normal local user is required.' >&2; exit 64; }
# The source app must be authenticated before any of its code is copied into root-owned locations.
/usr/bin/codesign --verify --deep --strict "$patchnap_app"
patchnap_requirement='anchor apple generic and identifier "com.patchnap.app" and certificate leaf[subject.OU] = "__PATCHNAP_TEAM_ID__"'
/usr/bin/codesign --verify -R "$patchnap_requirement" "$patchnap_app"
/usr/bin/codesign --verify --strict "$patchnap_app/Contents/MacOS/patchnap-store-helper"
[[ -f "$patchnap_app/Contents/Resources/mas" && ! -L "$patchnap_app/Contents/Resources/mas" ]] || { echo 'Bundled App Store tool missing.' >&2; exit 1; }
# Copy into a root-only staging directory first; validate the copy rather than trusting a mutable source.
patchnap_stage=$(/usr/bin/mktemp -d /private/tmp/patchnap-helper.XXXXXXXX)
trap '/bin/rm -rf "$patchnap_stage"' EXIT
/bin/chmod 700 "$patchnap_stage"
/usr/bin/ditto "$patchnap_app" "$patchnap_stage/Patchnap.app"
/usr/bin/codesign --verify --deep --strict -R "$patchnap_requirement" "$patchnap_stage/Patchnap.app"
/usr/bin/install -d -o root -g wheel -m 755 '/Library/Application Support/Patchnap' /Library/PrivilegedHelperTools
/usr/bin/install -o root -g wheel -m 755 "$patchnap_stage/Patchnap.app/Contents/MacOS/patchnap-store-helper" /Library/PrivilegedHelperTools/com.patchnap.store-helper
/usr/bin/install -o root -g wheel -m 755 "$patchnap_stage/Patchnap.app/Contents/Resources/mas" '/Library/Application Support/Patchnap/mas'
/usr/bin/shasum -a 256 '/Library/Application Support/Patchnap/mas' | /usr/bin/awk '{print $1}' > "$patchnap_stage/mas.sha256"
/usr/bin/install -o root -g wheel -m 644 "$patchnap_stage/mas.sha256" '/Library/Application Support/Patchnap/mas.sha256'
# The helper itself enforces argc, operation, decimal ID, installed receipt, active user, idle and power.
/usr/bin/printf '%s ALL=(root) NOPASSWD: /Library/PrivilegedHelperTools/com.patchnap.store-helper update *\n' "$patchnap_user" > "$patchnap_stage/sudoers"
/usr/sbin/visudo -cf "$patchnap_stage/sudoers"
/usr/bin/install -o root -g wheel -m 440 "$patchnap_stage/sudoers" /private/etc/sudoers.d/patchnap-store
printf 'App Store installation helper enabled.\n'
