#!/bin/bash
set -euo pipefail
[[ $EUID == 0 ]] || { echo 'Administrator authority required.' >&2; exit 1; }
# Remove authorization before removing executables.
/bin/rm -f /private/etc/sudoers.d/patchnap-store
/bin/rm -f /Library/PrivilegedHelperTools/com.patchnap.store-helper
/bin/rm -f '/Library/Application Support/Patchnap/mas' '/Library/Application Support/Patchnap/mas.sha256'
/bin/rmdir '/Library/Application Support/Patchnap' 2>/dev/null || true
