# OpenRGB Theme Sync

Paints every OpenRGB device with the current Omarchy theme's accent colour.
One colour across all devices — no per-device mapping to maintain.

## Install

Needs Omarchy with `omarchy-shell`, and the `openrgb` package.

The directory name must match the `id` in `manifest.json` — the shell keys
plugins by it, so a differently named clone will not load:

```bash
git clone https://github.com/perfektnacht/openrgb-theme-plugin \
  ~/.config/omarchy/plugins/perfektnacht.openrgb-theme

omarchy restart shell
```

That is enough to work. Theme switches now repaint on every change, but each one
pays for a full SMBus rescan — several seconds. The SDK server below brings that
down to ~35 ms.

### The SDK server

Not packaged with Omarchy; create the user unit yourself. No root required *if*
your user can already reach the hardware — see the permissions note below.

```ini
# ~/.config/systemd/user/openrgb-server.service
[Unit]
Description=OpenRGB SDK server (user session)
Documentation=https://openrgb.org/
After=graphical-session.target

[Service]
Type=simple
# --noautoconnect: this process *is* the server; without it OpenRGB also tries
# to connect to a server on startup.
ExecStart=/usr/bin/openrgb --server --noautoconnect
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
```

```bash
systemctl --user daemon-reload
systemctl --user enable --now openrgb-server
```

### Hardware permissions

Whether a non-root user can drive the devices varies by machine and by which
buses your hardware sits on. Motherboard and DRAM RGB usually go over SMBus,
which typically wants the `i2c-dev` module loaded and your user in a group with
access to `/dev/i2c-*`; USB peripherals go over hidraw and are usually fine
already. If devices show up in `openrgb --list-devices` but colours never land,
this is the first thing to check — OpenRGB's own
[udev rules](https://openrgb.org/) documentation covers the per-vendor detail.

Verify without touching hardware:

```bash
~/.config/omarchy/plugins/perfektnacht.openrgb-theme/bin/omarchy-openrgb-theme --dry-run
```

## How it works

`Color.accent` is a live property on the shell's `qs.Commons` singleton, and the
shell pushes new values through IPC whenever the theme changes. The service
binds to it, debounces 150 ms so one theme switch is one hardware write, and
shells out to `bin/omarchy-openrgb-theme`.

The helper talks to a persistent OpenRGB SDK server, so a theme switch costs
~35 ms instead of the several seconds a cold `openrgb` invocation spends
rescanning the SMBus.

## The saturation floor

RGB LEDs desaturate hard at brightness: a pastel that reads as blue on a monitor
renders as dim white on a keyboard. Eight of the 22 stock themes ship an accent
below 0.35 saturation.

The helper converts to HSV, raises S to a floor (default `0.7`), pushes V to
full, and converts back. Hue is untouched, so each theme stays recognisably
itself:

| Theme | Accent | Applied |
|---|---|---|
| solitude | `#798186` (sat 0.10) | `#4DBAFF` |
| tokyo-night | `#7aa2f7` (sat 0.51) | `#4D86FF` |
| kanagawa | `#dcd7ba` (sat 0.15) | `#FFE54D` |
| matte-black | `#e68e0d` (sat 0.94) | `#FF9D0E` |
| vantablack | `#8d8d8d` (sat 0.00) | `#FFFFFF` |

Pure greys are left alone on purpose — there is no hue to recover, and white is
the honest answer for the `vantablack` and `white` themes.

## Settings

Optional keys on the plugin's entry in `~/.config/omarchy/shell.json`. The
helper re-reads this on every apply, so edits take effect on the next theme
switch — or immediately via `omarchy-shell openrgb-theme apply`.

Settings are read by the helper rather than watched from QML on purpose:
Quickshell's `FileView` does not fire for writers that truncate before
rewriting (`cp`, and some editors), which made a watched version silently serve
stale config.

```json
{
  "id": "perfektnacht.openrgb-theme",
  "saturate": true,
  "minSaturation": 0.7,
  "minValue": 1.0,
  "brightness": 100,
  "staticDevices": ["Logitech G Pro RGB Mechanical Gaming Keyboard"]
}
```

| Key | Default | Meaning |
|---|---|---|
| `saturate` | `true` | Set `false` to send the theme colour untouched |
| `minSaturation` | `0.7` | Saturation floor, 0–1 |
| `minValue` | `1.0` | HSV brightness floor, 0–1 |
| `brightness` | unset | Device brightness percentage, 0–100, where supported |
| `staticDevices` | `[]` | Devices to send `Static` instead of `Direct` — see below |

### staticDevices

Direct is a live mode: the device holds the colour only while a host keeps
driving it. This helper runs once per theme change and exits, so a device whose
effects live in firmware reverts to whatever is stored there — usually a rainbow
cycle. Naming it here sends `Static` as well, which writes to onboard memory and
survives the helper exiting.

Entries are case-insensitive substrings matched against device names as
`openrgb --list-devices` reports them, so `"logitech g pro rgb"` is enough, and
`"logitech"` would catch a keyboard and mouse together. Names rather than
indices, because OpenRGB numbers devices in detection order and an index moves
when unrelated hardware comes or goes. A pattern matching nothing is reported
and skipped rather than failing the apply.

Empty by default: Static costs an onboard flash write per theme change, so this
is opt-in per device rather than the default for everything. Logitech keyboards
are the known case that needs it.

## Commands

```bash
omarchy-shell openrgb-theme status    # current accent and last applied colour
omarchy-shell openrgb-theme apply     # force a reapply

bin/omarchy-openrgb-theme                    # apply now
bin/omarchy-openrgb-theme --print            # show accent -> applied colour
bin/omarchy-openrgb-theme --print-settings   # effective settings as JSON
bin/omarchy-openrgb-theme --dry-run          # print the openrgb command
bin/omarchy-openrgb-theme --color 7aa2f7 --print
bin/omarchy-openrgb-theme --no-saturate      # flags override shell.json
```

## Editing the service

Bar widgets hot-reload on save; **service plugins do not**. The instance is
skipped once created, and Qt caches the component by URL, so neither
`rescanPlugins` nor a disable/enable cycle picks up a `Service.qml` edit. Use:

```bash
omarchy restart shell
```

Editing `bin/omarchy-openrgb-theme` needs no restart — it is re-executed on
every apply.

## The server

A user-level systemd unit — see [Install](#the-sdk-server) for the unit file and
the permissions it assumes.

```bash
systemctl --user status openrgb-server
```

The `openrgb` package also ships a system-wide `openrgb.service` that runs as
root. Don't enable both; two servers on port 6742 will fight.

Note: bare `openrgb` already autoconnects to a local server. Passing `--client`
*on top of* that connects twice and applies to every device twice over, which is
why the helper omits it.

## Tested on

Omarchy, OpenRGB 0.9+ (1.0rc3), against these six devices:

| Device | Type | Bus |
|---|---|---|
| MSI PRO B760-P WIFI (MS-7D98) | Motherboard | hidraw |
| ENE DRAM ×2 | DRAM | SMBus |
| Logitech G Pro RGB Mechanical | Keyboard | hidraw |
| Logitech G Pro HERO | Mouse | hidraw |
| Sony DualSense | Gamepad | hidraw |

Nothing here is device-specific — the helper sends one `openrgb --mode direct
--color` for everything, so any device OpenRGB can drive in Direct mode should
work. The list is what has actually had a colour put on it, not a limit.

## Known limits

- **Direct mode doesn't always survive suspend.** Reapply with
  `omarchy-shell openrgb-theme apply`. There's no Omarchy resume hook to attach
  this to; a systemd `system-sleep` script would need root.
- **The DRAM sticks are the flaky path.** SMBus writes can contend with other
  tooling touching i2c.
- **The server goes stale when USB re-enumerates.** OpenRGB opens each LED
  interface once at detection and holds the descriptor for the life of the
  server. Connecting a gamepad is enough to make a node come back under a new
  number, and writes to the old one are then accepted and silently discarded —
  the server keeps reporting the mode it believes it set while the hardware runs
  its stored effect. It looks exactly like this plugin not working. Fix:

  ```bash
  systemctl --user restart openrgb-server.service
  ```

  The helper warns about this when it can, by checking the `Location` paths in
  `--list-devices` against what exists. Note that not every controller reports a
  location — the Logitech keyboard does not — so detection leans on the devices
  that do. If a re-enumeration moves *only* an unreported device, the check stays
  silent.

## Debugging

Quickshell sends stdout and stderr to `/dev/null`, so the service's
`console.warn` output never reaches `journalctl`. Warnings land in Quickshell's
own log instead:

```bash
qs log --pid $(pgrep -f 'quickshell -n -p') -t 100
```

Anything from this plugin is prefixed `openrgb-theme:`. Running
`bin/omarchy-openrgb-theme` directly is the other way to see them, since the
helper writes its warnings to stderr.
