#!/usr/bin/env bash
#
# Remove the xr-driver game watchdog.
# The XRLinuxDriver installation itself is untouched.
#

set -euo pipefail

systemctl --user disable --now xr-driver-game-watchdog 2>/dev/null || true
rm -f "$HOME/.config/systemd/user/xr-driver-game-watchdog.service"
rm -f "$HOME/.local/bin/xr-driver-game-watchdog.sh"
systemctl --user daemon-reload 2>/dev/null || true

echo "Removed."
echo "Note: the driver config is unchanged. If you want the driver off permanently:  xr_driver_cli -d"
