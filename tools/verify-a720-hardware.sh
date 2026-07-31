#!/bin/sh
set -eu

FIRMWARE=/usr/lib/firmware/brcm/BCM20702A1-0489-e042.hcd
EXPECTED_SIZE=34904
EXPECTED_SHA256=9372ce8bfe400ef4560ca550007bd4bdf97b8b5ec70d24a45aa977050b6d8e4a
failures=0
warnings=0

pass() {
  printf 'PASS: %s\n' "$*"
}

warn() {
  printf 'WARN: %s\n' "$*" >&2
  warnings=$((warnings + 1))
}

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  failures=$((failures + 1))
}

echo '=== Lenovo IdeaCentre A720 hardware verification ==='

if [ -f "$FIRMWARE" ]; then
  actual_size=$(wc -c < "$FIRMWARE" | tr -d '[:space:]')
  actual_sha256=$(sha256sum "$FIRMWARE" | awk '{ print $1 }')

  if [ "$actual_size" = "$EXPECTED_SIZE" ] &&
     [ "$actual_sha256" = "$EXPECTED_SHA256" ]; then
    pass 'BCM20702A1 firmware file matches the verified size and SHA-256 digest'
  else
    fail "BCM20702A1 firmware file differs from the verified reference ($actual_size bytes, $actual_sha256)"
  fi
else
  fail "BCM20702A1 firmware file is missing: $FIRMWARE"
fi

if journalctl -b -k --no-pager --no-hostname 2>/dev/null |
   grep -q "BCM20702A1 'brcm/BCM20702A1-0489-e042.hcd' Patch"; then
  pass 'kernel reports loading the BCM20702A1 firmware patch this boot'
else
  warn 'kernel patch-load confirmation was not found or the kernel journal is not readable'
fi

if systemctl --user is-active --quiet obex.service; then
  pass 'Bluetooth OBEX user service is active'
else
  warn 'Bluetooth OBEX user service is not active'
fi

if systemctl --user is-active --quiet evolution-source-registry.service; then
  pass 'Evolution source registry is active'
else
  warn 'Evolution source registry is not active'
fi

if [ -d /etc/bluetooth ]; then
  mode=$(stat -c '%a' /etc/bluetooth)
  if [ "$mode" = 755 ]; then
    pass '/etc/bluetooth has the expected 0755 mode'
  else
    warn "/etc/bluetooth mode is $mode rather than 0755"
  fi
fi

if [ -d /var/lib/bluetooth ]; then
  mode=$(stat -c '%a' /var/lib/bluetooth)
  if [ "$mode" = 700 ]; then
    pass '/var/lib/bluetooth remains private at mode 0700'
  else
    fail "/var/lib/bluetooth mode is $mode rather than 0700"
  fi
fi

if grep -qxF nouveau /etc/initramfs-tools/modules 2>/dev/null; then
  pass 'Nouveau is requested in initramfs-tools/modules'
else
  warn 'Nouveau is not listed in /etc/initramfs-tools/modules'
fi

if command -v glxinfo >/dev/null 2>&1; then
  glx_output=$(glxinfo -B 2>/dev/null || true)
  if printf '%s\n' "$glx_output" | grep -q '^direct rendering: Yes$' &&
     printf '%s\n' "$glx_output" | grep -q 'Accelerated: yes'; then
    pass 'Mesa reports direct, accelerated rendering'
  else
    fail 'Mesa did not report direct, accelerated rendering'
  fi

  renderer=$(printf '%s\n' "$glx_output" | sed -n 's/^OpenGL renderer string: //p' | head -n 1)
  [ -n "$renderer" ] && printf 'INFO: OpenGL renderer: %s\n' "$renderer"
else
  warn 'glxinfo is unavailable; install mesa-utils to verify 3D acceleration'
fi

if command -v vdpauinfo >/dev/null 2>&1; then
  if vdpauinfo 2>/dev/null | grep -q '^H264_HIGH'; then
    pass 'VDPAU exposes an H.264 High decoder profile'
  else
    warn 'VDPAU did not expose the expected H.264 High decoder profile'
  fi
else
  warn 'vdpauinfo is unavailable'
fi

if command -v vainfo >/dev/null 2>&1; then
  if vainfo 2>/dev/null | grep -q 'VAProfileH264High.*VAEntrypointVLD'; then
    pass 'VA-API exposes H.264 High VLD decoding'
  else
    warn 'VA-API did not expose the expected H.264 High VLD entry point'
  fi
else
  warn 'vainfo is unavailable'
fi

system_failed=$(systemctl --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]')
user_failed=$(systemctl --user --failed --no-legend 2>/dev/null | sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]')

if [ "$system_failed" -eq 0 ]; then
  pass 'no failed system units'
else
  fail "$system_failed failed system unit(s)"
fi

if [ "$user_failed" -eq 0 ]; then
  pass 'no failed user units'
else
  fail "$user_failed failed user unit(s)"
fi

echo
echo "Summary: $failures failure(s), $warnings warning(s)"
[ "$failures" -eq 0 ]
