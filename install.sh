#!/usr/bin/env bash
#
# Install the xr-driver game watchdog.
# Requires XRLinuxDriver to be installed (https://github.com/wheaney/XRLinuxDriver).
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ ! -x "$HOME/.local/bin/xr_driver_cli" ] && ! command -v xr_driver_cli >/dev/null 2>&1; then
  echo "ERROR: xr_driver_cli not found. Install XRLinuxDriver first:" >&2
  echo "  https://github.com/wheaney/XRLinuxDriver" >&2
  exit 1
fi

mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
install -m 755 "$SCRIPT_DIR/xr-driver-game-watchdog.sh" "$HOME/.local/bin/xr-driver-game-watchdog.sh"
install -m 644 "$SCRIPT_DIR/xr-driver-game-watchdog.service" "$HOME/.config/systemd/user/xr-driver-game-watchdog.service"

systemctl --user daemon-reload
systemctl --user enable --now xr-driver-game-watchdog

echo "Installed."
echo "  watchdog: $HOME/.local/bin/xr-driver-game-watchdog.sh"
echo "  unit:     $HOME/.config/systemd/user/xr-driver-game-watchdog.service"
echo
echo "The driver is now only enabled while a game in the GAMES list is running."
echo "If the driver is currently enabled and you want it off right now:  xr_driver_cli -d"
echo "Check status:  systemctl --user status xr-driver-game-watchdog"
