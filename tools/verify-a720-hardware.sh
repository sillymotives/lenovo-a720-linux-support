#!/bin/sh
set -eu

FIRMWARE=/usr/lib/firmware/brcm/BCM20702A1-0489-e042.hcd
EXPECTED_SIZE=34904
EXPECTED_SHA256=9372ce8bfe400ef4560ca550007bd4bdf97b8b5ec70d24a45aa977050b6d8e4a
EXPECTED_DRIVER_VERSION=1.1.0
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

read_dmi() {
  cat "/sys/class/dmi/id/$1" 2>/dev/null || true
}

count_nonempty_lines() {
  sed '/^[[:space:]]*$/d' | wc -l | tr -d '[:space:]'
}

echo '=== Lenovo IdeaCentre A720 hardware verification ==='

vendor=$(read_dmi sys_vendor)
product=$(read_dmi product_name)
version=$(read_dmi product_version)
case "$vendor:$product:$version" in
  LENOVO:2564:*IdeaCentre\ A720*)
    pass 'DMI identity matches Lenovo IdeaCentre A720 type 2564'
    ;;
  *)
    fail "DMI identity is not the supported A720: $vendor / $product / $version"
    ;;
esac

if [ -d /sys/module/a720_wmi_handshake ]; then
  loaded_version=$(cat /sys/module/a720_wmi_handshake/version 2>/dev/null || true)
  if [ "$loaded_version" = "$EXPECTED_DRIVER_VERSION" ]; then
    pass "A720 WMI driver $EXPECTED_DRIVER_VERSION is loaded"
  elif [ -n "$loaded_version" ]; then
    warn "A720 WMI driver $loaded_version is loaded; expected $EXPECTED_DRIVER_VERSION"
  else
    warn 'loaded A720 WMI driver predates MODULE_VERSION support'
  fi

  if [ -r /sys/module/a720_wmi_handshake/parameters/request ]; then
    pass 'atomic A720 request snapshot interface is available'
  elif [ -r /sys/module/a720_wmi_handshake/parameters/request_seq ] &&
       [ -r /sys/module/a720_wmi_handshake/parameters/requested_volume ]; then
    warn 'only the legacy split A720 request interface is available'
  else
    fail 'A720 WMI request interface is unavailable'
  fi
else
  fail 'A720 WMI driver is not loaded'
fi

if ! command -v sha256sum >/dev/null 2>&1; then
  fail 'sha256sum is unavailable'
elif [ -f "$FIRMWARE" ]; then
  actual_size=$(wc -c < "$FIRMWARE" | tr -d '[:space:]')
  actual_sha256=$(sha256sum "$FIRMWARE" | awk '{ print $1 }')

  if [ "$actual_size" = "$EXPECTED_SIZE" ] &&
     [ "$actual_sha256" = "$EXPECTED_SHA256" ]; then
    pass 'BCM20702A1 firmware matches the verified size and SHA-256 digest'
  else
    fail "BCM20702A1 firmware differs ($actual_size bytes, $actual_sha256)"
  fi
else
  fail "BCM20702A1 firmware is missing: $FIRMWARE"
fi

if kernel_log=$(journalctl -b -k --no-pager --no-hostname 2>/dev/null); then
  if printf '%s\n' "$kernel_log" |
     grep -q "BCM20702A1 'brcm/BCM20702A1-0489-e042.hcd' Patch"; then
    pass 'kernel reports loading the BCM20702A1 firmware patch this boot'
  else
    warn 'kernel patch-load confirmation was not found this boot'
  fi
else
  warn 'kernel journal is not readable'
fi

if systemctl --user is-active --quiet obex.service 2>/dev/null; then
  pass 'Bluetooth OBEX user service is active'
else
  warn 'Bluetooth OBEX user service is not active'
fi

if systemctl --user is-active --quiet evolution-source-registry.service 2>/dev/null; then
  pass 'Evolution source registry is active'
else
  warn 'Evolution source registry is not active'
fi

if [ -d /etc/bluetooth ]; then
  mode=$(stat -c '%a' /etc/bluetooth)
  if [ "$mode" = 755 ]; then
    pass '/etc/bluetooth has mode 0755'
  else
    warn "/etc/bluetooth mode is $mode rather than 0755"
  fi
else
  warn '/etc/bluetooth does not exist'
fi

if [ -d /var/lib/bluetooth ]; then
  mode=$(stat -c '%a' /var/lib/bluetooth)
  if [ "$mode" = 700 ]; then
    pass '/var/lib/bluetooth remains private at mode 0700'
  else
    fail "/var/lib/bluetooth mode is $mode rather than 0700"
  fi
else
  warn '/var/lib/bluetooth does not exist'
fi

if grep -qxF nouveau /etc/initramfs-tools/modules 2>/dev/null; then
  pass 'Nouveau is requested in initramfs-tools/modules'
else
  warn 'Nouveau is not listed in /etc/initramfs-tools/modules'
fi

running_kernel=$(uname -r)
initrd="/boot/initrd.img-$running_kernel"
if command -v lsinitramfs >/dev/null 2>&1 && [ -r "$initrd" ]; then
  if initrd_listing=$(lsinitramfs "$initrd" 2>/dev/null); then
    if printf '%s\n' "$initrd_listing" |
       grep -qE '(^|/)nouveau\.ko(\.(xz|zst|gz))?$'; then
      pass 'running-kernel initramfs contains the Nouveau module'
    else
      warn 'running-kernel initramfs does not contain the Nouveau module'
    fi

    if printf '%s\n' "$initrd_listing" |
       grep -qE '(^|/)a720_wmi_handshake\.ko(\.(xz|zst|gz))?$'; then
      pass 'running-kernel initramfs contains the A720 WMI module'
    else
      fail 'running-kernel initramfs does not contain the A720 WMI module'
    fi
  else
    warn 'lsinitramfs could not read the running-kernel initramfs'
  fi
else
  warn 'cannot inspect the running-kernel initramfs'
fi

if command -v glxinfo >/dev/null 2>&1; then
  glx_output=$(glxinfo -B 2>/dev/null || true)
  if printf '%s\n' "$glx_output" | grep -q '^direct rendering: Yes$' &&
     printf '%s\n' "$glx_output" | grep -q 'Accelerated: yes'; then
    pass 'Mesa reports direct, accelerated rendering'
  else
    fail 'Mesa did not report direct, accelerated rendering'
  fi

  renderer=$(printf '%s\n' "$glx_output" |
    sed -n 's/^OpenGL renderer string: //p' | head -n 1)
  [ -n "$renderer" ] && printf 'INFO: OpenGL renderer: %s\n' "$renderer"
else
  warn 'glxinfo is unavailable; install mesa-utils to verify 3D acceleration'
fi

if command -v vdpauinfo >/dev/null 2>&1; then
  if vdpauinfo 2>/dev/null | grep -q '^H264_HIGH'; then
    pass 'VDPAU advertises an H.264 High decoder profile'
  else
    warn 'VDPAU did not advertise the expected H.264 High decoder profile'
  fi
else
  warn 'vdpauinfo is unavailable'
fi

if command -v vainfo >/dev/null 2>&1; then
  if vainfo 2>/dev/null | grep -q 'VAProfileH264High.*VAEntrypointVLD'; then
    pass 'VA-API advertises H.264 High VLD decoding'
  else
    warn 'VA-API did not advertise the expected H.264 High VLD entry point'
  fi
else
  warn 'vainfo is unavailable'
fi

if system_units=$(systemctl --failed --no-legend --plain 2>/dev/null); then
  system_failed=$(printf '%s\n' "$system_units" | count_nonempty_lines)
  if [ "$system_failed" -eq 0 ]; then
    pass 'no failed system units'
  else
    fail "$system_failed failed system unit(s)"
  fi
else
  warn 'could not query failed system units'
fi

if user_units=$(systemctl --user --failed --no-legend --plain 2>/dev/null); then
  user_failed=$(printf '%s\n' "$user_units" | count_nonempty_lines)
  if [ "$user_failed" -eq 0 ]; then
    pass 'no failed user units'
  else
    fail "$user_failed failed user unit(s)"
  fi
else
  warn 'could not query failed user units'
fi

echo
echo "Summary: $failures failure(s), $warnings warning(s)"
[ "$failures" -eq 0 ]
