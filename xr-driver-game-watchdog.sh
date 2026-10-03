#!/usr/bin/env bash
#
# xr-driver-game-watchdog
#
# Keeps the XREAL XR driver's mouse emulation tied to a game being in
# foreground, so that plugging in the glasses does NOT auto-activate head
# tracking. The driver is disabled by default; this watchdog enables it only
# while one of the games in GAMES is running, and disables it again when the
# game exits.
#
# State-sync (idempotent): it polls, reads the driver config, and only calls
# the CLI when the desired state differs from the actual state. So it is
# self-healing (if the config ever drifts, it corrects it) and never spams
# the CLI.
#
# How it works with the driver:
#   - xrDriver watches ~/.config/xr_driver/config.ini via inotify.
#   - `xr_driver_cli -e` / `-d` rewrites `disabled=false` / `disabled=true`
#     in that file, and the driver picks the change up immediately.
#   - The driver respects `disabled`: while disabled=true it never connects,
#     even with the glasses plugged in (verified in the driver source).
#
# To add a game: append its exact process name (what `pgrep -x` sees) to GAMES.

set -u

CONFIG="${HOME}/.config/xr_driver/config.ini"
CLI="${HOME}/.local/bin/xr_driver_cli"
POLL_SECONDS=2

# Exact process names (comm) to watch. Add one entry per game.
GAMES=(
  "eurotrucks2"
)

game_running() {
  local g
  for g in "${GAMES[@]}"; do
    if pgrep -x "$g" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}

# Read the current driver enabled/disabled state.
# Prints "enabled", "disabled", or "unknown" (config missing / no field).
driver_state() {
  if [ ! -f "$CONFIG" ]; then
    echo "unknown"; return
  fi
  if grep -q '^disabled=true' "$CONFIG" 2>/dev/null; then
    echo "disabled"
  elif grep -q '^disabled=false' "$CONFIG" 2>/dev/null; then
    echo "enabled"
  else
    echo "unknown"
  fi
}

set_enabled() {
  "$CLI" -e >/dev/null 2>&1
}
set_disabled() {
  "$CLI" -d >/dev/null 2>&1
}

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

log "watchdog start (poll=${POLL_SECONDS}s, games=${GAMES[*]})"

last_state=""
while true; do
  running=0
  game_running && running=1

  state="$(driver_state)"

  # Desired: enabled iff a game is running.
  if [ "$running" -eq 1 ]; then
    if [ "$state" = "disabled" ]; then
      log "game running -> enabling driver"
      set_enabled
      last_state="enabled"
    fi
  else
    if [ "$state" = "enabled" ]; then
      log "no game running -> disabling driver"
      set_disabled
      last_state="disabled"
    fi
  fi

  sleep "$POLL_SECONDS"
done
