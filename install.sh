#!/bin/sh
set -eu
[ "$(id -u)" -eq 0 ] || { echo "Run with: sudo ./install.sh" >&2; exit 1; }
USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || { echo "Run via sudo from the desktop user account." >&2; exit 1; }
USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
KVER=$(uname -r)

apt-get update
apt-get install -y build-essential dkms "linux-headers-$KVER" python3 pulseaudio-utils

SRC=/usr/src/a720-wmi-handshake-1.0.0
rm -rf "$SRC"
mkdir -p "$SRC"
cp "$ROOT/src/a720_wmi_handshake.c" "$ROOT/src/Makefile" "$ROOT/src/dkms.conf" "$SRC/"

dkms remove -m a720-wmi-handshake -v 1.0.0 --all >/dev/null 2>&1 || true
dkms add -m a720-wmi-handshake -v 1.0.0
dkms build -m a720-wmi-handshake -v 1.0.0
dkms install -m a720-wmi-handshake -v 1.0.0

cat > /etc/systemd/system/a720-wmi-handshake.service <<'EOF'
[Unit]
Description=Lenovo IdeaCentre A720 bezel WMI handshake
After=systemd-modules-load.service
Before=graphical.target

[Service]
Type=oneshot
ExecStart=/sbin/modprobe a720_wmi_handshake initialize=1 sync_volume=50 dump_response=0
ExecStartPost=/bin/sh -c 'for i in 1 2 3 4 5; do test -e /sys/module/a720_wmi_handshake/parameters/sync_volume && chmod 0666 /sys/module/a720_wmi_handshake/parameters/sync_volume && exit 0; sleep 1; done; exit 1'
RemainAfterExit=yes
ExecStop=/sbin/modprobe -r a720_wmi_handshake

[Install]
WantedBy=multi-user.target
EOF

install -d -o "$USER_NAME" -g "$USER_NAME" "$USER_HOME/.local/bin" "$USER_HOME/.config/systemd/user"
install -m 0755 -o "$USER_NAME" -g "$USER_NAME" "$ROOT/user/a720_volume_bridge.py" "$USER_HOME/.local/bin/a720_volume_bridge.py"
cat > "$USER_HOME/.config/systemd/user/a720-volume-bridge.service" <<'EOF'
[Unit]
Description=Lenovo IdeaCentre A720 bezel volume bridge
After=default.target

[Service]
Type=simple
ExecStart=%h/.local/bin/a720_volume_bridge.py
Restart=on-failure
RestartSec=3

[Install]
WantedBy=default.target
EOF
chown "$USER_NAME:$USER_NAME" "$USER_HOME/.config/systemd/user/a720-volume-bridge.service"

systemctl daemon-reload
# Replace any manually loaded diagnostic build with the installed DKMS build.
pkill -u "$USER_UID" -f a720_volume_bridge.py >/dev/null 2>&1 || true
systemctl stop a720-wmi-handshake.service >/dev/null 2>&1 || true
modprobe -r a720_wmi_handshake >/dev/null 2>&1 || true
systemctl enable --now a720-wmi-handshake.service

if [ -d "/run/user/$USER_UID" ]; then
  su -s /bin/sh "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user daemon-reload"
  su -s /bin/sh "$USER_NAME" -c "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user enable --now a720-volume-bridge.service"
else
  su -s /bin/sh "$USER_NAME" -c "systemctl --user enable a720-volume-bridge.service" || true
  echo "User service enabled; it will start at next login."
fi

echo
echo "Installed. Test the bezel now."
echo "Kernel status: systemctl status a720-wmi-handshake.service"
echo "User status:   systemctl --user status a720-volume-bridge.service"
