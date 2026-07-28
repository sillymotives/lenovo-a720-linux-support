#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo ./uninstall.sh" >&2; exit 1; }
USER_NAME=${SUDO_USER:-}
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
if [ -d "/run/user/$USER_UID" ]; then
  su -s /bin/sh "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user disable --now a720-volume-bridge.service" || true
fi
rm -f "$USER_HOME/.config/systemd/user/a720-volume-bridge.service" "$USER_HOME/.local/bin/a720_volume_bridge.py"
systemctl disable --now a720-wmi-handshake.service || true
rm -f /etc/systemd/system/a720-wmi-handshake.service
systemctl daemon-reload
dkms remove -m a720-wmi-handshake -v 1.0.0 --all || true
rm -rf /usr/src/a720-wmi-handshake-1.0.0
echo "A720 persistent driver removed."
