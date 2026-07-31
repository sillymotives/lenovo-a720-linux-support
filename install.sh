#!/bin/sh
set -eu

[ "$(id -u)" -eq 0 ] || {
  echo "Run with: sudo ./install.sh" >&2
  exit 1
}

USER_NAME=${A720_USER:-${SUDO_USER:-}}
[ -n "$USER_NAME" ] && [ "$USER_NAME" != root ] || {
  echo "Run via sudo, or set A720_USER to the desktop account." >&2
  exit 1
}

USER_HOME=$(getent passwd "$USER_NAME" | cut -d: -f6)
USER_UID=$(id -u "$USER_NAME")
USER_GID=$(id -g "$USER_NAME")
[ -n "$USER_HOME" ] && [ -d "$USER_HOME" ] || {
  echo "Could not resolve the desktop user's home directory." >&2
  exit 1
}

DMI_VENDOR=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)
DMI_PRODUCT=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
DMI_VERSION=$(cat /sys/class/dmi/id/product_version 2>/dev/null || true)

case "$DMI_VENDOR:$DMI_PRODUCT:$DMI_VERSION" in
  LENOVO:2564:*IdeaCentre\ A720*) ;;
  *)
    echo "This installer is restricted to the Lenovo IdeaCentre A720 type 2564." >&2
    echo "Detected: $DMI_VENDOR / $DMI_PRODUCT / $DMI_VERSION" >&2
    exit 1
    ;;
esac

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE_NAME=a720-wmi-handshake
MODULE_VERSION=1.1.0
OLD_MODULE_VERSION=1.0.0
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
SRC_BACKUP="${SRC}.backup.$$"
OLD_SRC="/usr/src/$MODULE_NAME-$OLD_MODULE_VERSION"
OLD_SRC_BACKUP="${OLD_SRC}.backup.$$"
source_replaced=0
new_installed=0
old_removed=0
old_kernels=

rollback_install() {
  status=$?
  trap - EXIT HUP INT TERM
  rm -rf "$SRC_TMP"

  if [ "$old_removed" -eq 1 ]; then
    echo "Installation failed; attempting to restore DKMS $OLD_MODULE_VERSION." >&2
    dkms remove -m "$MODULE_NAME" -v "$MODULE_VERSION" --all >/dev/null 2>&1 || true

    if [ "$source_replaced" -eq 1 ]; then
      rm -rf "$SRC"
      if [ -e "$SRC_BACKUP" ]; then
        mv "$SRC_BACKUP" "$SRC"
      fi
    fi

    rm -rf "$OLD_SRC"
    if [ -e "$OLD_SRC_BACKUP" ]; then
      mv "$OLD_SRC_BACKUP" "$OLD_SRC"
      dkms add -m "$MODULE_NAME" -v "$OLD_MODULE_VERSION" >/dev/null 2>&1 || true

      for kernel in $old_kernels; do
        [ -d "/lib/modules/$kernel" ] || continue
        if ! dkms build --force -m "$MODULE_NAME" -v "$OLD_MODULE_VERSION" -k "$kernel" ||
           ! dkms install --force -m "$MODULE_NAME" -v "$OLD_MODULE_VERSION" -k "$kernel"; then
          echo "CRITICAL: failed to restore DKMS $OLD_MODULE_VERSION for $kernel" >&2
        fi
      done
    else
      echo "CRITICAL: the previous DKMS source backup is unavailable." >&2
    fi
  elif [ "$source_replaced" -eq 1 ]; then
    if [ "$new_installed" -eq 0 ]; then
      rm -rf "$SRC"
      if [ -e "$SRC_BACKUP" ]; then
        mv "$SRC_BACKUP" "$SRC"
      fi
    else
      rm -rf "$SRC_BACKUP"
    fi
  fi

  exit "$status"
}

trap rollback_install EXIT
trap 'exit 1' HUP INT TERM
rm -rf "$SRC_TMP" "$SRC_BACKUP" "$OLD_SRC_BACKUP"

old_status=$(dkms status -m "$MODULE_NAME" -v "$OLD_MODULE_VERSION" 2>/dev/null || true)
new_status=$(dkms status -m "$MODULE_NAME" -v "$MODULE_VERSION" 2>/dev/null || true)

if [ -n "$old_status" ] && [ -n "$new_status" ]; then
  echo "Both DKMS $OLD_MODULE_VERSION and $MODULE_VERSION are registered." >&2
  echo "Refusing an ambiguous migration; remove the incomplete version manually." >&2
  exit 1
fi

if [ -n "$old_status" ]; then
  [ -d "$OLD_SRC" ] || {
    echo "DKMS $OLD_MODULE_VERSION is registered but its source tree is missing: $OLD_SRC" >&2
    exit 1
  }

  old_kernels=$(printf '%s\n' "$old_status" |
    sed -n 's|^[^,]*, \([^,]*\), [^:]*: installed$|\1|p')

  for kernel in $old_kernels; do
    [ -d "/lib/modules/$kernel" ] || continue
    [ -e "/lib/modules/$kernel/build/Makefile" ] || {
      echo "Cannot safely migrate DKMS $OLD_MODULE_VERSION for $kernel without headers." >&2
      exit 1
    }
  done

  cp -a "$OLD_SRC" "$OLD_SRC_BACKUP"
  old_removed=1
  dkms remove -m "$MODULE_NAME" -v "$OLD_MODULE_VERSION" --all
fi

mkdir -p "$SRC_TMP"
cp "$ROOT/src/a720_wmi_handshake.c" "$ROOT/src/Makefile" "$ROOT/src/dkms.conf" "$SRC_TMP/"

if [ -e "$SRC" ]; then
  mv "$SRC" "$SRC_BACKUP"
fi
mv "$SRC_TMP" "$SRC"
source_replaced=1

# Build the running kernel first. Until installation succeeds, the EXIT trap
# restores the previous source tree and any migrated DKMS 1.0.0 installation.
dkms build --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$RUNNING_KERNEL"
dkms install --force -m "$MODULE_NAME" -v "$MODULE_VERSION" -k "$RUNNING_KERNEL"
new_installed=1

installed_version=$(modinfo -k "$RUNNING_KERNEL" -F version a720_wmi_handshake 2>/dev/null || true)
[ "$installed_version" = "$MODULE_VERSION" ] || {
  echo "Installed module version is '${installed_version:-missing}', expected $MODULE_VERSION." >&2
  exit 1
}

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
    case " $old_kernels " in
      *" $kernel "*)
        echo "Failed to replace DKMS $OLD_MODULE_VERSION for fallback kernel $kernel." >&2
        exit 1
        ;;
      *)
        echo "Warning: DKMS refresh failed for fallback kernel $kernel" >&2
        ;;
    esac
  fi
done

rm -rf "$SRC_BACKUP"
if [ "$old_removed" -eq 1 ]; then
  rm -rf "$OLD_SRC" "$OLD_SRC_BACKUP"
fi
source_replaced=0
old_removed=0
trap - EXIT HUP INT TERM

install -D -m 0644 \
  "$ROOT/modprobe/a720-wmi-handshake.conf" \
  /etc/modprobe.d/a720-wmi-handshake.conf

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

install -d /etc/systemd/system/a720-wmi-handshake.service.d
cat > /etc/systemd/system/a720-wmi-handshake.service.d/access.conf <<EOF_ACCESS
[Service]
ExecStartPost=/usr/bin/chown root:$USER_GID /sys/module/a720_wmi_handshake/parameters/sync_volume
ExecStartPost=/usr/bin/chmod 0660 /sys/module/a720_wmi_handshake/parameters/sync_volume
EOF_ACCESS
chmod 0644 /etc/systemd/system/a720-wmi-handshake.service.d/access.conf

user_systemd="$USER_HOME/.config/systemd/user"
user_runtime="/run/user/$USER_UID"

if [ -d "$user_runtime" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=$user_runtime systemctl --user stop a720-volume-bridge.service" || true
fi

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
systemctl stop a720-wmi-handshake.service >/dev/null 2>&1 || true
systemctl enable --now a720-wmi-handshake.service

if [ -d /sys/module/a720_wmi_handshake ]; then
  loaded_version=$(cat /sys/module/a720_wmi_handshake/version 2>/dev/null || true)
  if [ "$loaded_version" != "$MODULE_VERSION" ]; then
    echo "A previous module version remains loaded; reboot to activate $MODULE_VERSION."
  fi
fi

if [ -d "$user_runtime" ]; then
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=$user_runtime systemctl --user daemon-reload"
  su -s /bin/sh "$USER_NAME" -c \
    "XDG_RUNTIME_DIR=$user_runtime systemctl --user enable --now a720-volume-bridge.service"
else
  install -d -o "$USER_UID" -g "$USER_GID" "$user_systemd/default.target.wants"
  ln -sfn ../a720-volume-bridge.service \
    "$user_systemd/default.target.wants/a720-volume-bridge.service"
  chown -h "$USER_UID:$USER_GID" \
    "$user_systemd/default.target.wants/a720-volume-bridge.service"
  echo "User service enabled; it will start at next login."
fi

echo
echo "Installed for kernels:$built_kernels"
echo "Kernel status: systemctl status a720-wmi-handshake.service"
echo "User status:   systemctl --user status a720-volume-bridge.service"
