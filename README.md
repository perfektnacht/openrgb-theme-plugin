# OpenRGB Theme Sync

Paints every OpenRGB device with the current Omarchy theme's accent colour.
One colour across all devices — no per-device mapping to maintain.

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
  "brightness": 100
}
```

| Key | Default | Meaning |
|---|---|---|
| `saturate` | `true` | Set `false` to send the theme colour untouched |
| `minSaturation` | `0.7` | Saturation floor, 0–1 |
| `minValue` | `1.0` | HSV brightness floor, 0–1 |
| `brightness` | unset | Device brightness percentage, 0–100, where supported |

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

A user-level systemd unit, no root required — direct hardware access already
works for this user via existing i2c and hidraw permissions.

```bash
systemctl --user status openrgb-server
```

The `openrgb` package also ships a system-wide `openrgb.service` that runs as
root. Don't enable both; two servers on port 6742 will fight.

Note: bare `openrgb` already autoconnects to a local server. Passing `--client`
*on top of* that connects twice and applies to every device twice over, which is
why the helper omits it.

## Known limits

- **Direct mode doesn't always survive suspend.** Reapply with
  `omarchy-shell openrgb-theme apply`. There's no Omarchy resume hook to attach
  this to; a systemd `system-sleep` script would need root.
- **The DRAM sticks are the flaky path.** SMBus writes can contend with other
  tooling touching i2c.
