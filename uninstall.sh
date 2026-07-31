#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "Run with: sudo ./uninstall.sh" >&2
  exit 1
}

USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || {
  echo "Run via sudo from the desktop user account." >&2
  exit 1
}

USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
MODULE_NAME=a720-wmi-handshake
MODULE_VERSION=1.0.0

if [ -d "/run/user/$USER_UID" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user disable --now a720-volume-bridge.service" || true
fi

rm -f \
  "$USER_HOME/.config/systemd/user/a720-volume-bridge.service" \
  "$USER_HOME/.config/systemd/user/a720-volume-bridge.service.d/audio-ready.conf" \
  "$USER_HOME/.local/bin/a720_volume_bridge.py"
rmdir "$USER_HOME/.config/systemd/user/a720-volume-bridge.service.d" 2>/dev/null || true

if [ -d "/run/user/$USER_UID" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user daemon-reload" || true
fi

systemctl disable --now a720-wmi-handshake.service || true
rm -f /etc/systemd/system/a720-wmi-handshake.service
systemctl daemon-reload

dkms remove -m "$MODULE_NAME" -v "$MODULE_VERSION" --all || true
rm -rf "/usr/src/$MODULE_NAME-$MODULE_VERSION"

if [ -f /etc/initramfs-tools/modules ]; then
  tmp=$(mktemp)
  trap 'rm -f "$tmp"' EXIT HUP INT TERM

  awk '
    $0 == "# Lenovo A720 bezel handshake" { skip_comment=1; next }
    skip_comment && $0 == "a720_wmi_handshake" { skip_comment=0; next }
    { skip_comment=0; print }
  ' /etc/initramfs-tools/modules > "$tmp"

  cat "$tmp" > /etc/initramfs-tools/modules
  update-initramfs -u -k all
fi

echo "A720 persistent driver removed."
echo "The optional Debian ALSA override is not removed automatically."
