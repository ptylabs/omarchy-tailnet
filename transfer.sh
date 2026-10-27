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
  echo "Uso: transfer.sh upload|download <destino> [carpeta-local]" >&2
  exit 1
fi

name="${dest#*@}"
name="${name%%.*}"
sock="${XDG_RUNTIME_DIR:-/tmp}/tailnet-ssh-$$"

cleanup() { ssh -S "$sock" -O exit "$dest" >/dev/null 2>&1; }
trap cleanup EXIT

fail() {
  omarchy-notification-send -g "󰣀" -u critical "$1" "$2" 2>/dev/null
  printf '\n%s: %s\nPulsa Enter para cerrar… ' "$1" "$2"
  read -r _
  exit 1
}

# Quote for the remote POSIX shell.
q() { printf "'%s'" "${1//\'/\'\\\'\'}"; }
remote() { ssh -S "$sock" "$dest" "$@"; }

files=()
if [[ $mode == upload ]]; then
  picked=$(omarchy-file-select --title "Subir a $name" --multiple) || true
  [[ -n $picked ]] || exit 0
  readarray -t files <<<"$picked"
fi

echo "Conectando con $dest…"
ssh -fNM -S "$sock" "$dest" || fail "No se pudo conectar con $name" "ssh $dest falló"
cwd=$(remote pwd) || fail "No se pudo leer $name" "El remoto no tiene un shell POSIX"

# Walks remote folders with fzf. Prints the chosen absolute paths, or the
# chosen destination folder when uploading.
browse() {
  local out key sel header
  while true; do
    if [[ $mode == upload ]]; then
      header="Subir ${#files[@]} elemento(s) → Enter: entrar · Ctrl-S: subir aquí · Esc: cancelar"
    else
      header="Enter: entrar/descargar · Tab: marcar varios · Ctrl-S: descargar esta carpeta · Esc: salir"
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
  what=$( ((${#files[@]} == 1)) && basename -- "${files[0]}" || echo "${#files[@]} elementos")
  echo "Subiendo $what a $name:$chosen…"
  scp -r -o ControlPath="$sock" -- "${files[@]}" "$dest:$chosen/" \
    || fail "No se pudo subir a $name" "$what → $chosen"
  omarchy-notification-send -g "󰕒" "Subido a $name" "$what → $chosen" 2>/dev/null
else
  readarray -t paths <<<"$chosen"
  sources=()
  for path in "${paths[@]}"; do sources+=("$dest:$path"); done
  what=$( ((${#paths[@]} == 1)) && basename -- "${paths[0]}" || echo "${#paths[@]} elementos")
  mkdir -p -- "$localdir"
  echo "Descargando $what de $name a $localdir…"
  scp -r -o ControlPath="$sock" -- "${sources[@]}" "$localdir/" \
    || fail "No se pudo descargar de $name" "$what"
  omarchy-notification-send -g "󰇚" "Descargado de $name" "$what → ${localdir/#$HOME/\~}" 2>/dev/null
fi

echo "Hecho."
sleep 1
