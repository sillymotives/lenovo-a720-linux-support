#!/bin/sh
set -eu

OUTPUT=${1:-a720-boot-audit.txt}

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
  systemctl --failed --no-pager || true

  echo
  echo '=== Failed user units ==='
  systemctl --user --failed --no-pager || true

  echo
  echo '=== Current boot warnings and errors ==='
  journal_command -b \
    --no-pager \
    --no-hostname \
    -o short-monotonic \
    -p warning..alert || true
} | tee "$OUTPUT"

echo
echo "Saved boot audit to: $OUTPUT"
echo "Review it before publishing; journals can contain usernames, device identifiers, network details, and third-party application data."
