# AdGuard VPN applet for Omarchy

An [Omarchy](https://omarchy.org) shell bar widget for controlling
[AdGuard VPN CLI](https://adguard-vpn.com/kb/adguard-vpn-for-linux/) — a shield
icon with a click-to-toggle panel, built for SOCKS mode where the VPN is a local
proxy (`127.0.0.1:1080`) that only explicitly configured apps use.

## Features

- Shield icon in the bar: outline shield with Wi-Fi waves and a dot;
  bright when connected, dim when disconnected (panel hero tints the waves
  with the theme accent while connected)
- Left-click opens the panel, right-click toggles the VPN, middle-click refreshes
- Panel shows status, location, mode, and the SOCKS proxy address
- Location picker: `list-locations` ping estimates sorted fastest-first,
  click a city (or the pinned "Fastest" row / press `f`) to connect; pings
  are live-measured, so the list refreshes on panel open and `r`, not on
  the status poll
- Favorites: star a city in the list (star button on the row, separate from
  the connect click); favorites pin below the "Fastest" row, ping-ordered,
  stored in `~/.local/state/omarchy/adguardvpn-favorites.json`
  (`XDG_STATE_HOME`-aware) and kept even when a city leaves the list
- Optimistic toggle: the switch reacts instantly, status polls catch up
  (default every 10 s, configurable via `refreshIntervalSec` in the manifest)
- SOCKS truth: in SOCKS mode a live listener probe (`/dev/tcp` connect)
  outranks the CLI's `status` line, which can report Disconnected in steady
  state while the proxy still works
- No sudo needed in SOCKS mode — TUN mode requires root and is not the target here

## Install

Managed by Omarchy as a git clone, so installs and updates come from `main`:

```bash
omarchy plugin add git@github.com:UnikZ/adguard-vpn-omarchy-applet.git --enable --yes
omarchy bar move unikz.adguardvpn --section right   # optional placement
```

Update to the latest `main`: `omarchy plugin update unikz.adguardvpn`.
Remove: `omarchy plugin remove unikz.adguardvpn`.

Requires the AdGuard VPN CLI at `/opt/adguardvpn_cli/adguardvpn-cli`
(override with the `ADGUARDVPN_CLI` env var).

## IPC

```bash
omarchy-shell unikz.adguardvpn status   # Connected | Disconnected | …
omarchy-shell unikz.adguardvpn start    # connect the VPN
omarchy-shell unikz.adguardvpn stop     # disconnect the VPN
omarchy-shell unikz.adguardvpn connectTo <city>  # connect to a specific location
omarchy-shell unikz.adguardvpn fastest   # connect to the lowest-ping location
omarchy-shell unikz.adguardvpn open     # open the panel
```

## Development

The installed plugin at `~/.config/omarchy/plugins/unikz.adguardvpn` is a
git-managed clone — treat it as **production**: the bar runs whatever is on
`main`. Develop in a separate checkout and deploy by push + update:

```bash
git clone git@github.com:UnikZ/adguard-vpn-omarchy-applet.git
# ...edit, commit, push...
omarchy plugin update unikz.adguardvpn   # pulls main into the installed copy
```

For rapid iteration against the live bar, temporarily swap production for a
symlink to the dev checkout (swap back with `omarchy plugin remove` +
`omarchy plugin add ...` afterwards). Note the symlink itself does not
hot-reload — apply each dev iteration with `omarchy restart shell`.

Plugin load errors land in the journal:

```bash
journalctl --user -t omarchy-shell -f
```

Layout follows the first-party plugins (`dropbox`, `tailscale` in
`/usr/share/omarchy/shell/plugins/panels/`):

- `manifest.json` — plugin metadata and settings schema
- `Model.js` — pure parsing of CLI output (ANSI stripping, status/config);
  covered by `node --test tests/`
- `Service.qml` — process wrappers, polling, optimistic toggle, watchdogs
- `AdguardIcon.qml` — native outline shield with Wi-Fi waves and a dot via
  `QtQuick.Shapes`; `outlineColor` for the shield, `contentColor` for waves
  (pass the theme accent while connected for a colored interior)
- `Panel.qml` — bar button + popup

Gotchas learned the hard way:

- `ShapePath` has no `visible` property — hide a path by setting its
  `strokeColor` to `"transparent"` instead.
- The hot-reloader can serve a stale cached component after an error;
  a full `omarchy restart shell` picks up the fix.
- The CLI's status output contains ANSI escapes; strip before parsing.

## Rolling back to TUN mode

```bash
/opt/adguardvpn_cli/adguardvpn-cli config set-mode tun
```

Then undo any app-side proxy settings pointing at `127.0.0.1:1080`, and disable
the widget if you no longer want it: `omarchy plugin disable unikz.adguardvpn`.
