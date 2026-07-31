#!/bin/sh
set -eu

umask 077
OUTPUT=${1:-a720-boot-audit.txt}
incomplete=0
tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

journal_command() {
  if [ "$(id -u)" -eq 0 ]; then
    journalctl "$@"
  elif command -v sudo >/dev/null 2>&1; then
    sudo journalctl "$@"
  else
    journalctl "$@"
  fi
}

{
  echo '=== Failed system units ==='
  if ! systemctl --failed --no-pager; then
    echo 'ERROR: could not query system units' >&2
    incomplete=1
  fi

  echo
  echo '=== Failed user units ==='
  if ! systemctl --user --failed --no-pager; then
    echo 'ERROR: could not query user units' >&2
    incomplete=1
  fi

  echo
  echo '=== Current boot warnings and errors ==='
  if ! journal_command -b \
    --no-pager \
    --no-hostname \
    -o short-monotonic \
    -p warning..alert; then
    echo 'ERROR: could not read the complete current-boot journal' >&2
    incomplete=1
  fi
} > "$tmp" 2>&1

tee "$OUTPUT" < "$tmp"

echo
echo "Saved boot audit to: $OUTPUT"
echo "This is not anonymized. Review it before publishing."
echo "Journals can contain usernames, addresses, device IDs, and application data."

[ "$incomplete" -eq 0 ]
