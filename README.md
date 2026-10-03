# xr-driver-game-watchdog

Tie [XRLinuxDriver](https://github.com/wheaney/XRLinuxDriver) mouse emulation to a game,
so plugging in your XREAL glasses does **not** auto-activate head tracking.
The driver is disabled by default; the watchdog enables it **only while a game
is running**, and disables it again when the game exits.

## Why

`XRLinuxDriver` is a systemd user service that, when enabled, turns head motion
into mouse movement. The problem: it is enabled *permanently*, so the moment you
plug in your glasses the mouse is hijacked — even when you're not gaming.
This tool makes the driver **game-gated** without touching the driver itself.

## How it works (no driver modification)

- `xrDriver` watches `~/.config/xr_driver/config.ini` via **inotify**.
- The driver **respects `disabled`**: while `disabled=true` it never connects to
  the glasses, even with them plugged in (verified in the driver source:
  `block_on_device_ready = force_quit || !driver_disabled() && device_present()`).
- `xr_driver_cli -e` / `-d` rewrite `disabled=false` / `disabled=true` into that
  file, which the driver picks up immediately.
- This watchdog is a small **idempotent** poller (every 2 s). It only calls the
  CLI when the desired state differs from the actual state, so it is self-healing
  and never spams the CLI.
  - a game in the list is running → enable the driver
  - no game is running → disable the driver

## Requirements

- [XRLinuxDriver](https://github.com/wheaney/XRLinuxDriver) installed
  (`xr_driver_cli` available).
- systemd (user session).

## Install

```bash
git clone https://github.com/issac-cyber/xr-driver-game-watchdog
cd xr-driver-game-watchdog
./install.sh
```

That's it. The watchdog starts now and on every login (and after reboots, if you
have lingering enabled for your user).

## Add more games

Edit the `GAMES` array at the top of `~/.local/bin/xr-driver-game-watchdog.sh`
and add the exact process name (what `pgrep -x` sees) of each game:

```bash
GAMES=(
  "eurotrucks2"     # Euro Truck Simulator 2 (native Linux binary)
  "another_game"    # add your own here
)
```

To find a game's process name while it is running: `ps -e -o comm | grep -i <part>`.
Restart the service after editing: `systemctl --user restart xr-driver-game-watchdog`.

## Behavior notes

- **Default state is disabled.** Plug in the glasses → the mouse is not touched.
  Start a game in the list → the driver enables within ~2 s. Quit the game → it
  disables again.
- **It enforces the state.** If you run `xr_driver_cli -e` manually while no game
  is running, the watchdog will disable it again on the next poll. To keep the
  driver enabled for non-game use, stop the watchdog first:
  `systemctl --user stop xr-driver-game-watchdog`.
- **The driver itself is unchanged.** Nothing in XRLinuxDriver is modified or
  patched.

## Uninstall

```bash
./uninstall.sh
```

Removes the watchdog script and unit. The XRLinuxDriver installation and its
config are untouched.

## Files

| File | Purpose |
|---|---|
| `xr-driver-game-watchdog.sh` | the poller (state-sync, idempotent) |
| `xr-driver-game-watchdog.service` | systemd **user** unit (`%h` = your home) |
| `install.sh` | installs the script + unit, enables & starts it |
| `uninstall.sh` | removes the script + unit |
