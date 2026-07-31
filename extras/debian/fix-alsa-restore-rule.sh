#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "Run with: sudo ./extras/debian/fix-alsa-restore-rule.sh" >&2
  exit 1
}

vendor=${A720_ALSA_VENDOR_RULE:-/usr/lib/udev/rules.d/90-alsa-restore.rules}
override=${A720_ALSA_OVERRIDE_RULE:-/etc/udev/rules.d/90-alsa-restore.rules}

[ -f "$vendor" ] || {
  echo "Vendor ALSA restore rule not found: $vendor" >&2
  exit 1
}

if grep -q 'LABEL="alsa_restore_std"' "$vendor"; then
  if [ -f "$override" ]; then
    echo "Vendor rule is fixed, but $override still takes precedence."
    echo "Review it and remove it when the vendor fix is trusted."
  else
    echo "Vendor rule already contains LABEL=\"alsa_restore_std\"; no override needed."
  fi
  exit 0
fi

if ! grep -q 'GOTO="alsa_restore_std"' "$vendor"; then
  echo "Vendor rule does not match the known Debian label bug; refusing to alter it." >&2
  exit 1
fi

label_count=$(grep -c '^LABEL="alsa_restore_go"$' "$vendor" || true)
[ "$label_count" -eq 2 ] || {
  echo "Expected exactly two alsa_restore_go labels; refusing unknown layout." >&2
  exit 1
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT HUP INT TERM

awk '
  /^LABEL="alsa_restore_go"$/ {
    seen++
    if (seen == 2) {
      print "LABEL=\"alsa_restore_std\""
      next
    }
  }
  { print }
' "$vendor" > "$tmp"

grep -q 'LABEL="alsa_restore_std"' "$tmp" || {
  echo "Failed to construct corrected rule." >&2
  exit 1
}

if [ -e "$override" ]; then
  if cmp -s "$tmp" "$override"; then
    echo "Corrected ALSA rule override is already installed: $override"
    exit 0
  fi

  echo "Existing override differs from the generated correction: $override" >&2
  echo "Refusing to overwrite an administrator-managed udev rule." >&2
  exit 1
fi

install -D -m 0644 "$tmp" "$override"
echo "Installed update-safe ALSA rule override: $override"
echo "It will take effect for newly added sound devices and after the next boot."
