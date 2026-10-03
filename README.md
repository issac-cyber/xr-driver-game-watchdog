# xr-driver-game-watchdog

Tie [XRLinuxDriver](https://github.com/wheaney/XRLinuxDriver) mouse emulation to a game,
so plugging in your XREAL glasses does **not** auto-activate head tracking.
The driver is disabled by default; the watchdog enables it **only while a game
is running**, and disables it again when the game exits.

This repo also documents the **complete XREAL One Pro setup on Ubuntu** —
the parts that are not in the driver's README and that took a full night to
diagnose (NCM networking + OSD stabilizer).

---

## Part 1 — Complete XREAL One Pro setup on Ubuntu

Goal: glasses connected by USB-C, head motion controls the mouse (for
mouse-look games like ETS2), fully automatic on plug/unplug and reboot.

> The One / One Pro / 1S use **TCP over USB-NCM**, not HID (only the older
> Air series uses HID). This is the single most important fact, and the cause
> of almost every "it won't connect" problem.

### Step 1 — Install XRLinuxDriver

```bash
curl -L -o ~/Downloads/xr_driver_setup \
  https://github.com/wheaney/XRLinuxDriver/releases/latest/download/xr_driver_setup
chmod +x ~/Downloads/xr_driver_setup
sudo ~/Downloads/xr_driver_setup
```

(x86_64 and AARCH64. Re-run the same script to update the driver.)

### Step 2 — Create the NCM network profile (One series only)

The glasses are `169.254.2.1`; the host **must** be `169.254.2.2/24` **on the
NCM interface** (the one bound to `cdc_ncm`, not `cdc_ether`). The interface
name is derived from the glasses' MAC, so find it:

```bash
ip -br link | grep enx
for i in /sys/class/net/enx*; do
  echo "$(basename $i) → $(basename $(readlink $i/device/driver))"
done
# the one showing "cdc_ncm" is the target (e.g. enxfcd2b6adcc6d)
```

Create a persistent profile (auto-connects on every plug and reboot):

```bash
sudo nmcli connection add type ethernet con-name xreal-one-ncm ifname <NCM-ifname> \
  ipv4.method manual ipv4.addresses 169.254.2.2/24 ipv4.never-default yes \
  ipv6.method ignore connection.autoconnect yes
```

(On Ubuntu the NM backend is netplan; the profile lands in
`/etc/netplan/90-NM-<uuid>.yaml`. That's normal.)

> ⚠️ The two classic failures, both diagnosed from first principles:
> 1. putting the address on the `cdc_ether` interface instead of `cdc_ncm`, and
> 2. using the wrong subnet (`169.254.1.1/16`). The glasses actively ARP for
> `169.254.2.2` on the NCM link — if they can't reach it, port 52998 never
> comes up.

### Step 3 — Turn off Stabilizer / Anchor on the glasses

On the glasses OSD: **double-click the X key → Spatial Screen → Stabilizer → off**
(and disable Anchor too).

**This is mandatory.** While the X1 chip's Stabilizer is on, it consumes the IMU
for its own screen-stabilization and does **not** expose the IMU stream — so
port 52998 stays dead, ICMP fails, and only ARP works. (Documented in the
XRLinuxDriver README and VertoXR's device docs for the One series.)

### Step 4 — Verify

```bash
# glasses active, driver log shows "Device connected" → "Device calibration complete"
tail -f ${XDG_STATE_HOME:-~/.local/state}/xr_driver/driver.log

# glasses side: ARP reachable + TCP 52998 open
ip neigh show | grep 169.254
python3 -c "import socket; s=socket.socket(); s.settimeout(3); s.connect(('169.254.2.1',52998)); print('52998 OPEN')"
```

If the driver log loops `Device driver connection attempt failed` → `Retrying`,
you are almost certainly missing Step 2 (wrong interface/subnet) or Step 3
(stabilizer still on).

### Step 5 — Install this watchdog (optional, recommended)

```bash
git clone https://github.com/issac-cyber/xr-driver-game-watchdog
cd xr-driver-game-watchdog
./install.sh
```

Now the driver stays **disabled** until a game in the `GAMES` list is running.
Part 2 below explains it.

### Ongoing notes (learned the hard way)

- **Drift (gyro bias):** on every (re)connect the driver runs a 1000-sample IMU
  calibration (~6 s after "Device connected", log shows `Device calibration
  complete`). **Hold the glasses completely still for ~10 s when you plug them
  in** — if your hand is moving during calibration the bias is calibrated wrong
  and the mouse drifts continuously. Re-plugging while still fixes it. A
  software deadzone (`xr_driver_cli -dz`) does **not** fix constant drift.
- **Display:** the glasses appear as an extra (third) display. To show a game
  on them: make the glasses the **Primary Display** in GNOME Display Settings,
  then launch the game fullscreen (on Wayland, dragging a window across
  displays is unreliable — don't rely on it).
- **Sensitivity:** the default `mouse_sensitivity=30` is very sensitive;
  `xr_driver_cli --mouse-sensitivity 15` is a good starting point (12/10 lower,
  18/20 higher). `--recenter` resets a drifting center; `--invert-x` /
  `--invert-y` flip a reversed axis.
- **Big-screen vs head tracking are mutually exclusive modes:** for the
  171″-style anchored big-screen experience, keep the glasses' Stabilizer/Anchor
  **on** and don't use the driver; for in-game head tracking, they must be
  **off** and the driver is used.

---

## Part 2 — The watchdog

### Why

`XRLinuxDriver` is a systemd user service that, when enabled, turns head motion
into mouse movement. The problem: it is enabled *permanently*, so the moment you
plug in your glasses the mouse is hijacked — even when you're not gaming.
This tool makes the driver **game-gated** without touching the driver itself.

### How it works (no driver modification)

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

### Install (watchdog)

```bash
git clone https://github.com/issac-cyber/xr-driver-game-watchdog
cd xr-driver-game-watchdog
./install.sh
```

The watchdog starts now and on every login (and after reboots, if you have
lingering enabled for your user).

### Add more games

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

### Behavior notes

- **Default state is disabled.** Plug in the glasses → the mouse is not touched.
  Start a game in the list → the driver enables within ~2 s. Quit the game → it
  disables again.
- **It enforces the state.** If you run `xr_driver_cli -e` manually while no game
  is running, the watchdog will disable it again on the next poll. To keep the
  driver enabled for non-game use, stop the watchdog first:
  `systemctl --user stop xr-driver-game-watchdog`.
- **The driver itself is unchanged.** Nothing in XRLinuxDriver is modified or
  patched.

### Uninstall

```bash
./uninstall.sh
```

Removes the watchdog script and unit. The XRLinuxDriver installation and its
config are untouched.

### Files

| File | Purpose |
|---|---|
| `xr-driver-game-watchdog.sh` | the poller (state-sync, idempotent) |
| `xr-driver-game-watchdog.service` | systemd **user** unit (`%h` = your home) |
| `install.sh` | installs the script + unit, enables & starts it |
| `uninstall.sh` | removes the script + unit |
