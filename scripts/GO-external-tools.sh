#!/data/data/com.termux/files/usr/bin/bash
set -u -o pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

bash "$HERE/install-external-tools.sh"
install_rc=$?

if [ -f "${FORGE_SURGEON_CONFIG:-$HOME/.forge-surgeon/config.json}" ]; then
  bash "$HERE/enable-external-tool-profiles.sh" || true
fi

bash "$HERE/verify-external-tools.sh"
verify_rc=$?

if [ "$install_rc" -ne 0 ] || [ "$verify_rc" -ne 0 ]; then
  echo "RESULT: HOLD — inspect ~/forge-tools/receipts and verification output"
  exit 4
fi

echo "RESULT: PASS — installer and verification reported no HOLDs"
