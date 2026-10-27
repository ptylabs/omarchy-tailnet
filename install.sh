#!/bin/bash
# Copies the plugin into the Omarchy user plugin dir (symlinks are not allowed
# by the plugin validator) and enables it in the bar.
set -euo pipefail

SRC="$(cd "$(dirname "$0")" && pwd)"
ID="$(jq -r .id "$SRC/manifest.json")"
DEST="$HOME/.config/omarchy/plugins/$ID"

omarchy plugin validate "$SRC"
mkdir -p "$DEST"
rsync -a --delete --exclude install.sh --exclude .git "$SRC/" "$DEST/"
echo "Installed to $DEST"

# Hot reload keeps serving cached QML for this plugin, so restart the shell.
omarchy restart shell >/dev/null 2>&1 || true
sleep 2

if [[ ${1:-} != --no-enable ]] && ! jq -e --arg id "$ID" '[.. | objects | select(.id? == $id)] | length > 0' "$HOME/.config/omarchy/shell.json" >/dev/null 2>&1; then
  sleep 1
  omarchy plugin enable "$ID"
fi
