#!/usr/bin/env bash
# Dump every flavor the clipboard is currently offering, and show the plain
# flavor byte-exactly. Run this on the machine that has Slack / Facebook open.
#
#   1. copy something in the app
#   2. ./clipdump.sh <label>
#
# Writes ./clipdump/<label>.{types,plain,html} and prints the plain flavor as
# hex so trailing spaces, NBSP, CRLF and stripped backticks are all visible.
set -u
label="${1:-sample}"
out="clipdump"; mkdir -p "$out"

dump() { # $1=type $2=file
  if command -v wl-paste >/dev/null 2>&1; then wl-paste --no-newline --type "$1" 2>/dev/null > "$2"
  elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -t "$1" -o 2>/dev/null > "$2"
  elif command -v pbpaste >/dev/null 2>&1; then
    case "$1" in text/html) osascript -e 'the clipboard as «class HTML»' 2>/dev/null | \
        sed 's/^«data HTML//; s/»$//' | xxd -r -p > "$2" ;;
      *) pbpaste > "$2" ;; esac
  elif command -v powershell.exe >/dev/null 2>&1; then
    case "$1" in text/html) powershell.exe -NoProfile -Command \
        "Get-Clipboard -TextFormatType Html" 2>/dev/null | tr -d '\r' > "$2" ;;
      *) powershell.exe -NoProfile -Command "Get-Clipboard -Raw" 2>/dev/null > "$2" ;; esac
  else echo "no clipboard tool found (want wl-paste, xclip, pbpaste, or powershell.exe)" >&2; exit 1
  fi
}

# what flavors are on offer
if command -v wl-paste >/dev/null 2>&1; then wl-paste --list-types
elif command -v xclip >/dev/null 2>&1; then xclip -selection clipboard -t TARGETS -o
elif command -v pbpaste >/dev/null 2>&1; then osascript -e 'clipboard info'
elif command -v powershell.exe >/dev/null 2>&1; then powershell.exe -NoProfile -Command \
  "[Windows.Forms.Clipboard]::GetDataObject().GetFormats() -join [char]10" 2>/dev/null
fi > "$out/$label.types"

dump text/plain "$out/$label.plain"
dump text/html  "$out/$label.html"

echo "=== flavors offered"; cat "$out/$label.types"
echo "=== plain flavor, $(wc -c < "$out/$label.plain") bytes"
cat "$out/$label.plain"
echo "=== plain flavor as hex (look for 60 = backtick, 3E = '>', 0D = CR, C2A0 = NBSP)"
command -v xxd >/dev/null 2>&1 && xxd "$out/$label.plain" || od -An -tx1z "$out/$label.plain"
echo "=== html flavor, $(wc -c < "$out/$label.html") bytes (saved, not printed)"
