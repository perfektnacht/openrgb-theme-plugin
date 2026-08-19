# OpenRGB Theme Sync

Paints every OpenRGB device to match the current Omarchy theme. Each stock theme
has a hand-picked colour; anything else falls back to the theme's accent. One
colour across all devices — no per-device mapping to maintain.

## Install

```bash
git clone https://github.com/perfektnacht/openrgb-theme-plugin \
  ~/.config/omarchy/plugins/perfektnacht.openrgb-theme && omarchy restart shell
```

Needs Omarchy with `omarchy-shell`, and the `openrgb` package. The directory
name must match the `id` in `manifest.json` — the shell keys plugins by it, so a
differently named clone will not load.

That is enough to work. Theme switches now repaint on every change, but each one
pays for a full SMBus rescan — several seconds. [The SDK
server](#the-sdk-server) brings that down to ~35 ms.

## Update

```bash
git -C ~/.config/omarchy/plugins/perfektnacht.openrgb-theme pull && omarchy restart shell
```

## Remove

```bash
rm -rf ~/.config/omarchy/plugins/perfektnacht.openrgb-theme && omarchy restart shell
```

Devices keep whatever colour was last written until something else drives them.
If you also created the SDK server unit and want it gone:

```bash
systemctl --user disable --now openrgb-server
rm ~/.config/systemd/user/openrgb-server.service
systemctl --user daemon-reload
```

## The SDK server

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

## Hardware permissions

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

The accent is only the *trigger*. The helper decides the colour itself, by
reading the theme slug from `~/.local/state/omarchy/current/theme.name` — which
`omarchy-theme-set` writes before it pushes the new palette over IPC, so it is
already current by the time the service fires.

The helper talks to a persistent OpenRGB SDK server, so a theme switch costs
~35 ms instead of the several seconds a cold `openrgb` invocation spends
rescanning the SMBus.

## The colours

Each stock theme gets a colour picked for it, sent to the hardware verbatim:

| Theme | | Theme | |
|---|---|---|---|
| catppuccin-latte | `#FFE0A8` vanilla | miasma | `#B2AE9E` gray |
| catppuccin | `#9B4DFF` purple | nord | `#1E3FB4` dark blue |
| ethereal | `#3A5BFF` blue | osaka-jade | `#10C878` jade |
| everforest | `#4FBF5A` green | retro-82 | `#E03A0F` martian red |
| flexoki-light | `#FFF8EC` white | ristretto | `#8C4A1E` brown |
| gruvbox | `#A0E85F` light green | rose-pine | `#FF5F9E` pink |
| hackerman | `#1FE81F` Xbox green | solitude | `#F2E2BC` vanilla |
| kanagawa | `#F3DD5C` yellow | tokyo-night | `#B78CFF` light purple |
| last-horizon | `#A9AFB5` gray | vantablack | `#FFFFFF` white |
| lumon | `#12C9B4` teal | white | `#FFFFFF` white |
| lupine | `#8B2BE8` purple | matte-black | `#FF9410` golden orange |

These bypass the saturation lift below. A table entry *is* the LED colour, so
remapping it would overrule the choice — and the `minValue` floor would
specifically destroy the two entries that depend on being dark, `ristretto`
brown and `nord` dark blue. Those two will read dim rather than vivid; that is
what "brown" and "dark blue" cost on a device whose only lever is how hard it
drives the emitters.

`vantablack` and `white` are deliberately the same white, so the hardware cannot
tell those two apart. Every other pair is at least 10 dE76 apart; the closest
are the ones sharing a colour word — `catppuccin` / `lupine` (both purple, 10.1)
and `catppuccin-latte` / `solitude` (both vanilla, 11.3).

`kanagawa` is the accent pipeline's own output, kept unchanged because it had
already landed on the right yellow.

Set `themeColors: false` to ignore the table entirely and drive everything off
the accent, the way this worked before.

## The saturation floor

This applies to the accent fallback — a custom or third-party theme with no
table entry — and to an explicit `--color`.

RGB LEDs desaturate hard at brightness: a pastel that reads as blue on a monitor
renders as dim white on a keyboard. Eight of the 22 stock themes ship an accent
below 0.35 saturation.

The helper converts to HSV and remaps S into `[minSaturation, 1]` and V into
`[minValue, 1]` — a lerp, not a clamp. Hue is untouched, so each theme stays
recognisably itself:

| Accent | Applied |
|---|---|
| `#798186` (sat 0.10) | `#56A4D5` |
| `#7aa2f7` (sat 0.51) | `#3877FC` |
| `#dcd7ba` (sat 0.15) | `#F3DD5C` |
| `#e68e0d` (sat 0.94) | `#F69506` |
| `#8d8d8d` (sat 0.00) | `#D7D7D7` |

Pure greys keep their neutrality on purpose — there is no hue to recover — but
they still take the brightness lift.

**Why a lerp and not a clamp.** The first version used `max(S, 0.7)` with V
pinned to `1.0`. That put every theme on a single ring of the colour solid where
only hue survived, and 14 of the 22 stock accents live in the 130–240° arc — so
adjacent themes came out visually identical and a theme switch looked like the
plugin had simply not fired. The worst offenders were `lumon` → `#4DC0FF` and
`solitude` → `#4DBAFF`, 4.1 dE76 apart. Remapping preserves ordering, so
anything that differs on screen differs on the hardware: that pair went to 11.4
apart. Hand-picked colours are the more direct answer to the same problem, which
is why the table came later — but the remap still carries every theme this
plugin has never heard of.

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
  "themeColors": true,
  "saturate": true,
  "minSaturation": 0.55,
  "minValue": 0.65,
  "brightness": 100,
  "staticDevices": ["Logitech G Pro RGB Mechanical Gaming Keyboard"]
}
```

| Key | Default | Meaning |
|---|---|---|
| `themeColors` | `true` | Set `false` to ignore the per-theme table and use the accent for every theme |
| `saturate` | `true` | Set `false` to send the accent untouched — no effect on table colours, which are never lifted |
| `minSaturation` | `0.55` | Bottom of the remapped saturation range, 0–1 |
| `minValue` | `0.65` | Bottom of the remapped HSV brightness range, 0–1 |
| `brightness` | unset | Device brightness percentage, 0–100, where supported |
| `staticDevices` | `[]` | Devices to send `Static` instead of `Direct` — see below |

### staticDevices

Direct is a live mode, driven by the host for as long as it keeps writing. This
helper runs once per theme change and exits, which breaks two kinds of device:

- **Firmware effects take back over.** Logitech keyboards revert to whatever is
  stored onboard, usually a rainbow cycle, the moment the writer goes away.
- **The chain never fully lights.** MSI's ARGB headers stream per-LED in Direct
  and the board drops the tail of the chain, so case fans daisy-chained off
  JRAINBOW sit *dark* while the CPU cooler and everything else on the same board
  take the colour correctly. This reads as "the plugin didn't fire", but the
  server has the right colour buffered for every LED — the board just isn't
  driving them.

Naming a device here sends it `Static` instead, which writes to onboard memory
and hands the chain to the board's own MCU.

Entries are case-insensitive substrings matched against device names as
`openrgb --list-devices` reports them, so `"logitech g pro rgb"` is enough, and
`"logitech"` would catch a keyboard and mouse together. Names rather than
indices, because OpenRGB numbers devices in detection order and an index moves
when unrelated hardware comes or goes. A pattern matching nothing is reported
and skipped rather than failing the apply.

Everything goes out in one `openrgb` invocation, with `-d` repeated per device
so Direct and Static devices are set together. An earlier version ran a global
Direct pass and then corrected the Static devices, which blinked the MSI fans
off for the second it took to reconnect.

Empty by default: Static costs an onboard flash write per theme change, so this
is opt-in per device rather than the default for everything. Logitech keyboards
and MSI motherboard ARGB headers are the known cases that need it.

The author's machine, as a worked example — a G Pro that would otherwise cycle,
and a B760-P whose JRAINBOW fans would otherwise stay dark:

```json
"staticDevices": [
  "Logitech G Pro RGB Mechanical Gaming Keyboard",
  "MSI PRO B760-P WIFI"
]
```

## Commands

```bash
omarchy-shell openrgb-theme status    # where the colour came from, and what landed
omarchy-shell openrgb-theme apply     # force a reapply

bin/omarchy-openrgb-theme                    # apply now
bin/omarchy-openrgb-theme --print            # show chosen -> applied colour
bin/omarchy-openrgb-theme --print-settings   # effective settings as JSON
bin/omarchy-openrgb-theme --dry-run          # print the openrgb command
bin/omarchy-openrgb-theme --color 7aa2f7 --print
bin/omarchy-openrgb-theme --no-theme-colors --print   # force the accent path
bin/omarchy-openrgb-theme --no-saturate      # flags override shell.json
```

`--print` and a successful apply both report which path ran — `theme:<slug>` for
a table hit, `accent` for the fallback, `explicit` for `--color`:

```
$ bin/omarchy-openrgb-theme --print
theme:solitude #F2E2BC -> #F2E2BC

$ bin/omarchy-openrgb-theme --no-theme-colors --print
accent #798186 -> #56A4D5
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

## Checking the server

A user-level systemd unit — see [The SDK server](#the-sdk-server) for the unit
file and the permissions it assumes.

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

## Security

Reviewed against the [Omarchy Plugin Marketplace][mp]'s pre-submission security
scan on 19 August 2026, at commit `42a2b76`.

**This is a self-review, not a marketplace audit.** Nobody from the marketplace
has reviewed this repository. Omarchy plugins run unsandboxed as upstream code,
so no scan — this one included — makes a plugin safe. It is published so you can
check the claims rather than take them.

**No code changes were needed.** What the scan confirmed:

- The only network activity is the loopback connection to the OpenRGB SDK
  server on `127.0.0.1:6742`. Nothing leaves the machine.
- Every external command is a `subprocess.run([...])` argument array. There is
  no `shell=True` and no shell string anywhere.
- It writes no files at all. It reads three: `colors.toml`, `theme.name` and
  `shell.json`.
- The theme name is used only as a lookup key — never a path, a command, or
  text rendered on screen.

Found something this missed? Report it privately through the marketplace's
[security policy][sec], or open an issue here.

[mp]: https://github.com/HANCORE-linux/omarchy-plugin-marketplace
[sec]: https://github.com/HANCORE-linux/omarchy-plugin-marketplace/blob/main/SECURITY.md

## License

MIT — see [LICENSE](LICENSE). No third-party code is bundled or vendored here;
the plugin is a QML service plus one Python helper, both written for it.

It drives software you install yourself, and does not redistribute any of it:

| Dependency | Licence | Role |
|------------|---------|------|
| [OpenRGB](https://openrgb.org) | GPL-2.0-or-later | The `openrgb` client and the SDK server this talks to on `127.0.0.1:6742` |
| Omarchy 4+ | MIT | Plugin host, and the source of the theme this follows |
| Quickshell | LGPL-3.0-only | QML runtime, used through imports as a system library |
| Python 3 | PSF-2.0 | Runs `bin/omarchy-openrgb-theme` |

The only network activity is that loopback connection to the OpenRGB SDK
server. Nothing leaves the machine, and the plugin writes no files — it reads
`colors.toml`, `theme.name` and `shell.json`, and nothing else.
