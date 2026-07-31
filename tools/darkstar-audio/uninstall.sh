#!/usr/bin/env bash
set -Eeuo pipefail

[ "$(id -u)" -eq 0 ] || {
    echo 'Run this uninstaller as root.' >&2
    false
}

systemctl disable --now darkstar-shutdown-jingle.service \
    >/dev/null 2>&1 || true

rm -f -- \
    /etc/systemd/system/darkstar-shutdown-jingle.service \
    /usr/local/libexec/darkstar-shutdown-jingle \
    /etc/initramfs-tools/hooks/darkstar-boot-audio \
    /etc/initramfs-tools/scripts/init-premount/darkstar-boot-jingle \
    /usr/local/share/darkstar/darkstar_boot.wav \
    /usr/local/share/darkstar/darkstar_shutdown.wav

systemctl daemon-reload
update-initramfs -u -k all

echo 'Darkstar boot and shutdown jingles removed.'
echo 'No EFI files or EFI variables were modified.'
