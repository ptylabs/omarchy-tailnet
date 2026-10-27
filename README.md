# Tailnet (ptylabs.tailnet)

Omarchy bar widget for your Tailscale network, based on the built-in
`omarchy.tailscale` plugin (MIT, Omarchy; `TailscaleIcon.qml` is reused as is).

- Tailnet name and every device, online and offline
- Services each device exposes: a TCP probe of a configurable port list over
  the tailnet, plus this machine's Tailscale Serve/Funnel routes
- SSH to any device in a new terminal (`tailscale ssh` when the peer runs
  Tailscale SSH, plain `ssh` otherwise)
- Upload and download files and folders over SSH/scp:
  - Upload: choose "Files" (several) or "Folder", then browse the remote
    folders with fzf and press `Ctrl-S` to upload into the current one
  - Download: browse the remote with fzf (`Tab` selects several, `Ctrl-S` takes
    the whole current folder), then choose where to save; cancelling saves to
    `~/Downloads`

## Usage

Each device shows only its name and detected services. On the right of each
row:

- 󰣀 SSH
- 󰓢 transfer: opens a box with **Upload** (left) and **Download** (right)
- 󰆏 copy: opens a card to pick the IP or the MagicDNS alias

Hover an offline device to see when it was last seen. Press `?` (or the help
icon) for every keyboard shortcut.

In the bar: left click opens the panel, right click toggles Tailscale, middle
click refreshes and rescans.

Clicking a service chip opens web services in the browser, `ssh` in a
terminal, and copies `host:port` for anything else.

## Settings

From the widget settings in the bar: refresh interval, scan interval, ports to
probe, SSH user, SSH target (MagicDNS or IP), download folder and whether to
show offline devices.

## Requirements

- `tailscale` CLI on `PATH`
- `ssh`, `scp` and `fzf` for SSH and transfers
- `wl-copy` for copy actions

## Install / update

From GitHub:

    omarchy plugin add https://github.com/ptylabs/omarchy-tailnet --enable

From a local checkout:

    ./install.sh

Copies the plugin to `~/.config/omarchy/plugins/ptylabs.tailnet/` and enables
it. Run it again after every change in this directory (it restarts the shell so
the changes load).
