#!/bin/sh
set -eu

EXPECTED_NAME=BCM20702A1-0489-e042.hcd
EXPECTED_SIZE=34904
EXPECTED_SHA256=9372ce8bfe400ef4560ca550007bd4bdf97b8b5ec70d24a45aa977050b6d8e4a
DEST=/usr/lib/firmware/brcm/$EXPECTED_NAME

usage() {
  echo "Usage: sudo $0 /path/to/$EXPECTED_NAME" >&2
  exit 2
}

[ "$(id -u)" -eq 0 ] || {
  echo "Run this installer through sudo." >&2
  exit 1
}

[ "$#" -eq 1 ] || usage
SOURCE=$1

[ -f "$SOURCE" ] || {
  echo "Firmware source is not a regular file: $SOURCE" >&2
  exit 1
}

command -v sha256sum >/dev/null 2>&1 || {
  echo "sha256sum is required to validate the firmware." >&2
  exit 1
}

actual_size=$(wc -c < "$SOURCE" | tr -d '[:space:]')
actual_sha256=$(sha256sum "$SOURCE" | awk '{ print $1 }')

[ "$actual_size" = "$EXPECTED_SIZE" ] || {
  echo "Unexpected firmware size: $actual_size bytes" >&2
  echo "Expected: $EXPECTED_SIZE bytes" >&2
  exit 1
}

[ "$actual_sha256" = "$EXPECTED_SHA256" ] || {
  echo "Unexpected firmware SHA-256: $actual_sha256" >&2
  echo "Expected: $EXPECTED_SHA256" >&2
  exit 1
}

if [ -e "$DEST" ]; then
  installed_size=$(wc -c < "$DEST" | tr -d '[:space:]')
  installed_sha256=$(sha256sum "$DEST" | awk '{ print $1 }')

  if [ "$installed_size" = "$EXPECTED_SIZE" ] &&
     [ "$installed_sha256" = "$EXPECTED_SHA256" ]; then
    echo "Validated firmware is already installed: $DEST"
    exit 0
  fi

  echo "Refusing to overwrite a different existing firmware file: $DEST" >&2
  echo "Move or inspect it manually before retrying." >&2
  exit 1
fi

install -D -m 0644 "$SOURCE" "$DEST"

echo "Installed validated Broadcom firmware: $DEST"
echo "This repository does not distribute the firmware blob."
echo "By using this helper, you confirm that you obtained the source lawfully."
echo "Reboot, or safely re-enumerate the Bluetooth controller, then verify the kernel log."
