#!/bin/bash
# Usage: transfer.sh upload|download <ssh-destination> [download-dir]
#
# Runs inside a terminal so ssh can prompt for passwords or host keys. One
# multiplexed ssh connection serves the remote browser and the copy, so a
# password is asked for at most once.

set -uo pipefail

mode="${1:-}"
dest="${2:-}"
localdir="${3:-}"
[[ -n $localdir ]] || localdir="$HOME/Downloads"
localdir="${localdir/#\~/$HOME}"

if [[ $mode != upload && $mode != download ]] || [[ -z $dest ]]; then
  echo "Usage: transfer.sh upload|download <destination> [local-dir]" >&2
  exit 1
fi

name="${dest#*@}"
name="${name%%.*}"
sock="${XDG_RUNTIME_DIR:-/tmp}/tailnet-ssh-$$"

cleanup() { ssh -S "$sock" -O exit "$dest" >/dev/null 2>&1; }
trap cleanup EXIT

fail() {
  omarchy-notification-send -g "󰣀" -u critical "$1" "$2" 2>/dev/null
  printf '\n%s: %s\nPress Enter to close… ' "$1" "$2"
  read -r _
  exit 1
}

# Quote for the remote POSIX shell.
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
remote() { ssh -S "$sock" "$dest" "$@"; }

files=()
if [[ $mode == upload ]]; then
  # The portal chooser picks either files or a folder, never both at once.
  kind=$(printf '%s\n' "Files" "Folder" | fzf --reverse --height=~6 --header "What do you want to upload to $name?") || exit 0
  if [[ $kind == Folder ]]; then
    picked=$(omarchy-file-select --title "Upload folder to $name" --directory) || true
  else
    picked=$(omarchy-file-select --title "Upload to $name" --multiple) || true
  fi
  [[ -n $picked ]] || exit 0
  readarray -t files <<<"$picked"
fi

echo "Connecting to $dest…"
ssh -fNM -S "$sock" "$dest" || fail "Could not connect to $name" "ssh $dest failed"
cwd=$(remote pwd) || fail "Could not read $name" "The remote has no POSIX shell"

# Walks remote folders with fzf. Prints the chosen absolute paths, or the
# chosen destination folder when uploading.
browse() {
  local out key sel header
  while true; do
    if [[ $mode == upload ]]; then
      header="Upload ${#files[@]} item(s) → Enter: open · Ctrl-S: upload here · Esc: cancel"
    else
      header="Enter: open/download · Tab: select multiple · Ctrl-S: download this folder · Esc: quit"
    fi

    out=$( { echo "../"; remote "cd $(q "$cwd") && ls -1Ap" | grep -v '^\./$\|^\.\./$'; } \
      | fzf --multi --reverse --expect=ctrl-s --header "$header" --prompt "$name:$cwd/ ") || return 1

    key=$(head -n1 <<<"$out")
    sel=$(tail -n +2 <<<"$out")

    if [[ $key == ctrl-s ]]; then
      printf '%s\n' "$cwd"
      return 0
    fi
    [[ -n $sel ]] || continue

    if [[ $(wc -l <<<"$sel") -eq 1 && $sel == */ ]]; then
      if [[ $sel == ../ ]]; then
        cwd=$(dirname -- "$cwd")
      else
        cwd="${cwd%/}/${sel%/}"
      fi
      continue
    fi

    # Uploads only pick folders; Enter on a file just stays put.
    [[ $mode == upload ]] && continue

    while IFS= read -r entry; do
      [[ $entry == ../ ]] && continue
      printf '%s\n' "${cwd%/}/${entry%/}"
    done <<<"$sel"
    return 0
  done
}

chosen=$(browse) || exit 0
[[ -n $chosen ]] || exit 0

if [[ $mode == upload ]]; then
  what=$( ((${#files[@]} == 1)) && basename -- "${files[0]}" || echo "${#files[@]} items")
  echo "Uploading $what to $name:$chosen…"
  scp -r -o ControlPath="$sock" -- "${files[@]}" "$dest:$chosen/" \
    || fail "Could not upload to $name" "$what → $chosen"
  omarchy-notification-send -g "󰕒" "Uploaded to $name" "$what → $chosen" 2>/dev/null
else
  readarray -t paths <<<"$chosen"
  # Cancelling the folder chooser falls back to the configured folder.
  target=$(omarchy-file-select --title "Save to… (cancel = ${localdir/#$HOME/\~})" --directory) || true
  [[ -n $target ]] && localdir="$target"
  sources=()
  for path in "${paths[@]}"; do sources+=("$dest:$path"); done
  what=$( ((${#paths[@]} == 1)) && basename -- "${paths[0]}" || echo "${#paths[@]} items")
  mkdir -p -- "$localdir"
  echo "Downloading $what from $name to $localdir…"
  scp -r -o ControlPath="$sock" -- "${sources[@]}" "$localdir/" \
    || fail "Could not download from $name" "$what"
  omarchy-notification-send -g "󰇚" "Downloaded from $name" "$what → ${localdir/#$HOME/\~}" 2>/dev/null
fi

echo "Done."
sleep 1
