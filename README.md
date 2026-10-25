# omarchy-adguardvpn

An [Omarchy](https://omarchy.org) shell bar widget for controlling
[AdGuard VPN CLI](https://adguard-vpn.com/kb/adguard-vpn-for-linux/) — a shield
icon with a click-to-toggle panel, built for SOCKS mode where the VPN is a local
proxy (`127.0.0.1:1080`) that only explicitly configured apps use.

## Features

- Shield icon in the bar: bright + checked when connected, dim when disconnected
- Left-click opens the panel, right-click toggles the VPN, middle-click refreshes
- Panel shows status, location, mode, and the SOCKS proxy address
- Click-to-copy rows for the proxy URI and a curl test command
- Optimistic toggle: the switch reacts instantly, status polls catch up
  (default every 10 s, configurable via `refreshIntervalSec` in the manifest)
- No sudo needed in SOCKS mode — TUN mode requires root and is not the target here

## Install

The Omarchy shell only discovers plugins under `~/.config/omarchy/plugins/`, so
install by symlinking this checkout:

```bash
ln -s "$PWD" ~/.config/omarchy/plugins/unikz.adguardvpn
omarchy plugin enable unikz.adguardvpn
omarchy restart shell
```

Requires the AdGuard VPN CLI at `/opt/adguardvpn_cli/adguardvpn-cli`
(override with the `ADGUARDVPN_CLI` env var) and `wl-copy` for copy actions.

## IPC

```bash
omarchy-shell unikz.adguardvpn status   # Connected | Disconnected | …
omarchy-shell unikz.adguardvpn start    # connect the VPN
omarchy-shell unikz.adguardvpn stop     # disconnect the VPN
omarchy-shell unikz.adguardvpn open     # open the panel
```

## Development

Edits under this directory hot-reload into the running shell; if a change
doesn't apply, `omarchy restart shell`. Plugin load errors land in the journal:

```bash
journalctl --user -t omarchy-shell -f
```

Layout follows the first-party plugins (`dropbox`, `tailscale` in
`/usr/share/omarchy/shell/plugins/panels/`):

- `manifest.json` — plugin metadata and settings schema
- `Model.js` — pure parsing of CLI output (ANSI stripping, status/config)
- `Service.qml` — process wrappers, polling, optimistic toggle, watchdogs
- `AdguardIcon.qml` — native shield via `QtQuick.Shapes`
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
