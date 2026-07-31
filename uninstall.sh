#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "Run with: sudo ./uninstall.sh" >&2
  exit 1
}

USER_NAME=${A720_USER:-${SUDO_USER:-}}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || {
  echo "Run via sudo, or set A720_USER to the desktop account." >&2
  exit 1
}

USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
MODULE_NAME=a720-wmi-handshake
MODULE_VERSION=1.1.0
user_systemd="$USER_HOME/.config/systemd/user"
user_runtime="/run/user/$USER_UID"

if [ -d "$user_runtime" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=$user_runtime systemctl --user disable --now a720-volume-bridge.service" || true
fi

rm -f \
  "$user_systemd/a720-volume-bridge.service" \
  "$user_systemd/a720-volume-bridge.service.d/audio-ready.conf" \
  "$user_systemd/default.target.wants/a720-volume-bridge.service" \
  "$USER_HOME/.local/bin/a720_volume_bridge.py"
rmdir "$user_systemd/a720-volume-bridge.service.d" 2>/dev/null || true
rmdir "$user_systemd/default.target.wants" 2>/dev/null || true

if [ -d "$user_runtime" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=$user_runtime systemctl --user daemon-reload" || true
fi

systemctl disable --now a720-wmi-handshake.service || true
if grep -q '^a720_wmi_handshake ' /proc/modules 2>/dev/null; then
  if ! /usr/sbin/modprobe -r a720_wmi_handshake; then
    echo "Warning: the running module could not be unloaded; reboot is required." >&2
  fi
fi
rm -f \
  /etc/systemd/system/a720-wmi-handshake.service \
  /etc/systemd/system/a720-wmi-handshake.service.d/access.conf \
  /etc/modprobe.d/a720-wmi-handshake.conf
rmdir /etc/systemd/system/a720-wmi-handshake.service.d 2>/dev/null || true
systemctl daemon-reload

dkms remove -m "$MODULE_NAME" -v "$MODULE_VERSION" --all || true
# Remove the historical pre-hardening version as well. DKMS may otherwise
# restore it as the original module when version 1.1.0 is removed.
dkms remove -m "$MODULE_NAME" -v 1.0.0 --all || true
rm -rf "/usr/src/$MODULE_NAME-$MODULE_VERSION" \
  "/usr/src/$MODULE_NAME-1.0.0"

if [ -f /etc/initramfs-tools/modules ]; then
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT HUP INT TERM

  awk '
    $0 == "# Lenovo A720 bezel handshake" { skip_comment=1; next }
    skip_comment && $0 == "a720_wmi_handshake" { skip_comment=0; next }
    { skip_comment=0; print }
  ' /etc/initramfs-tools/modules > "$tmp"

  mode=$(stat -c '%a' /etc/initramfs-tools/modules)
  owner=$(stat -c '%u' /etc/initramfs-tools/modules)
  group=$(stat -c '%g' /etc/initramfs-tools/modules)
  install -o "$owner" -g "$group" -m "$mode" \
    "$tmp" /etc/initramfs-tools/modules
  update-initramfs -u -k all
fi

echo "A720 persistent driver removed."
echo "Reboot to reset any firmware-side subscription state left by the loaded module."
echo "The optional Debian ALSA and Bluetooth changes are not removed automatically."
