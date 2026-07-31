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

source_snapshot=$(mktemp)
corrected=$(mktemp)
trap 'rm -f "$source_snapshot" "$corrected"' EXIT HUP INT TERM
install -m 0600 "$vendor" "$source_snapshot"

if [ -L "$override" ]; then
  echo "Refusing symlink override destination: $override" >&2
  exit 1
fi

if grep -qx 'LABEL="alsa_restore_std"' "$source_snapshot"; then
  if [ -f "$override" ]; then
    if cmp -s "$source_snapshot" "$override"; then
      echo "Vendor rule is fixed and the local override is now redundant."
      echo "Review and remove: $override"
      exit 0
    fi

    echo "Vendor rule is fixed, but a different local override still takes precedence:" >&2
    echo "$override" >&2
    echo "Review the override before treating the vendor repair as active." >&2
    exit 1
  fi

  echo "Vendor rule already contains LABEL=\"alsa_restore_std\"; no override needed."
  exit 0
fi

if ! grep -qx 'GOTO="alsa_restore_std"' "$source_snapshot"; then
  echo "Vendor rule does not match the known Debian label bug; refusing to alter it." >&2
  exit 1
fi

label_count=$(grep -c '^LABEL="alsa_restore_go"$' "$source_snapshot" || true)
[ "$label_count" -eq 2 ] || {
  echo "Expected exactly two alsa_restore_go labels; refusing unknown layout." >&2
  exit 1
}

awk '
  /^LABEL="alsa_restore_go"$/ {
    seen++
    if (seen == 2) {
      print "LABEL=\"alsa_restore_std\""
      next
    }
  }
  { print }
' "$source_snapshot" > "$corrected"

grep -qx 'LABEL="alsa_restore_std"' "$corrected" || {
  echo "Failed to construct corrected rule." >&2
  exit 1
}

if [ -e "$override" ]; then
  if cmp -s "$corrected" "$override"; then
    echo "Corrected ALSA rule override is already installed: $override"
    exit 0
  fi

  echo "Existing override differs from the generated correction: $override" >&2
  echo "Refusing to overwrite an administrator-managed udev rule." >&2
  exit 1
fi

install -D -m 0644 "$corrected" "$override"
echo "Installed update-safe ALSA rule override: $override"
echo "It will take effect for newly added sound devices and after the next boot."
