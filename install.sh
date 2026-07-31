#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "Run with: sudo ./install.sh" >&2
  exit 1
}

USER_NAME=${SUDO_USER:-}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || {
  echo "Run via sudo from the desktop user account." >&2
  exit 1
}

USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")
[ -n "$USER_HOME" ] && [ -d "$USER_HOME" ] || {
  echo "Could not resolve the desktop user's home directory." >&2
  exit 1
}

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE_NAME=a720-wmi-handshake
MODULE_VERSION=1.0.0
RUNNING_KERNEL=$(uname -r)
running_tree="/lib/modules/$RUNNING_KERNEL"

apt-get update
apt-get install -y build-essential dkms python3 pulseaudio-utils

if [ ! -e "$running_tree/build/Makefile" ]; then
  apt-get install -y "linux-headers-$RUNNING_KERNEL"
fi

[ -e "$running_tree/build/Makefile" ] || {
  echo "Headers for the running kernel $RUNNING_KERNEL are unavailable." >&2
  exit 1
}

for module_dir in /lib/modules/*; do
  [ -d "$module_dir" ] || continue
  kernel=${module_dir##*/}
  [ "$kernel" = "$RUNNING_KERNEL" ] && continue
  [ -e "$module_dir/build/Makefile" ] && continue

  package="linux-headers-$kernel"
  if apt-get install -y "$package"; then
    [ -e "$module_dir/build/Makefile" ] ||
      echo "Warning: $package installed but no build tree appeared for $kernel" >&2
  else
    echo "Warning: no installable headers are available for fallback kernel $kernel" >&2
  fi
done

SRC="/usr/src/$MODULE_NAME-$MODULE_VERSION"
SRC_TMP="${SRC}.tmp.$$"
rm -rf "$SRC_TMP"
mkdir -p "$SRC_TMP"
trap 'rm -rf "$SRC_TMP"' EXIT HUP INT TERM
cp "$ROOT/src/a720_wmi_handshake.c" "$ROOT/src/Makefile" "$ROOT/src/dkms.conf" "$SRC_TMP/"
rm -rf "$SRC"
mv "$SRC_TMP" "$SRC"
trap - EXIT HUP INT TERM

# --force rebuilds and reinstalls this version without deleting a known-good
# module first. A failed build therefore leaves the currently installed module
# available for that kernel.
dkms build --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$RUNNING_KERNEL"
dkms install --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$RUNNING_KERNEL"
built_kernels=" $RUNNING_KERNEL"

for module_dir in /lib/modules/*; do
  [ -d "$module_dir" ] || continue
  kernel=${module_dir##*/}
  [ "$kernel" = "$RUNNING_KERNEL" ] && continue

  if [ ! -e "$module_dir/build/Makefile" ]; then
    echo "Warning: skipping $kernel because its headers are unavailable" >&2
    continue
  fi

  if dkms build --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$kernel" &&
     dkms install --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$kernel"; then
    built_kernels="$built_kernels $kernel"
  else
    echo "Warning: DKMS refresh failed for fallback kernel $kernel; any previously installed module was left in place" >&2
  fi
done

if [ -f /etc/initramfs-tools/modules ]; then
  if ! grep -qxF a720_wmi_handshake /etc/initramfs-tools/modules; then
    printf '\n# Lenovo A720 bezel handshake\na720_wmi_handshake\n' >> /etc/initramfs-tools/modules
  fi

  for kernel in $built_kernels; do
    if [ -e "/boot/initrd.img-$kernel" ]; then
      update-initramfs -u -k "$kernel"
    fi
  done
fi

install -m 0644 \
  "$ROOT/systemd/a720-wmi-handshake.service" \
  /etc/systemd/system/a720-wmi-handshake.service

user_systemd="$USER_HOME/.config/systemd/user"
install -d -o "$USER_UID" -g "$USER_GID" \
  "$USER_HOME/.local/bin" \
  "$user_systemd/a720-volume-bridge.service.d"

install -m 0755 -o "$USER_UID" -g "$USER_GID" \
  "$ROOT/user/a720_volume_bridge.py" \
  "$USER_HOME/.local/bin/a720_volume_bridge.py"

install -m 0644 -o "$USER_UID" -g "$USER_GID" \
  "$ROOT/systemd/a720-volume-bridge.service" \
  "$user_systemd/a720-volume-bridge.service"

install -m 0644 -o "$USER_UID" -g "$USER_GID" \
  "$ROOT/systemd/a720-volume-bridge.service.d/audio-ready.conf" \
  "$user_systemd/a720-volume-bridge.service.d/audio-ready.conf"

systemctl daemon-reload

# Replace any manually loaded diagnostic build with the installed DKMS build.
pkill -u "$USER_UID" -f a720_volume_bridge.py >/dev/null 2>&1 || true
systemctl stop a720-wmi-handshake.service >/dev/null 2>&1 || true
modprobe -r a720_wmi_handshake >/dev/null 2>&1 || true
systemctl enable --now a720-wmi-handshake.service

if [ -d "/run/user/$USER_UID" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user daemon-reload"
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=/run/user/$USER_UID systemctl --user enable --now a720-volume-bridge.service"
else
  su -s /bin/sh "$USER_NAME" -c \
    "systemctl --user enable a720-volume-bridge.service" || true
  echo "User service enabled; it will start at next login."
fi

echo
echo "Installed for kernels:$built_kernels"
echo "Kernel status: systemctl status a720-wmi-handshake.service"
echo "User status:   systemctl --user status a720-volume-bridge.service"
