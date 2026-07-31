#!/usr/bin/env bash
set -Eeuo pipefail
umask 022

SOURCE_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
FILES_DIR="$SOURCE_DIR/files"
SHARE_DIR='/usr/local/share/darkstar'
HOOK='/etc/initramfs-tools/hooks/darkstar-boot-audio'
TRIGGER='/etc/initramfs-tools/scripts/init-premount/darkstar-boot-jingle'
HELPER='/usr/local/libexec/darkstar-shutdown-jingle'
UNIT='/etc/systemd/system/darkstar-shutdown-jingle.service'

[ "$(id -u)" -eq 0 ] || {
    echo 'Run this installer as root.' >&2
    false
}

for COMMAND in \
    python3 \
    aplay \
    amixer \
    update-initramfs \
    lsinitramfs \
    systemctl \
    systemd-analyze \
    install
do
    command -v "$COMMAND" >/dev/null 2>&1 || {
        echo "Missing required command: $COMMAND" >&2
        false
    }
done

aplay -l 2>/dev/null | grep -q 'card [0-9][0-9]*: PCH ' || {
    echo 'The expected PCH ALSA playback device was not found.' >&2
    false
}

TEMP_DIR=$(mktemp -d)
cleanup()
{
    rm -rf -- "$TEMP_DIR"
}
trap cleanup EXIT

python3 "$SOURCE_DIR/generate-jingles.py" --output-dir "$TEMP_DIR"

install -d -m 0755 "$SHARE_DIR"
install -m 0644 "$TEMP_DIR/darkstar_boot.wav" \
    "$SHARE_DIR/darkstar_boot.wav"
install -m 0644 "$TEMP_DIR/darkstar_shutdown.wav" \
    "$SHARE_DIR/darkstar_shutdown.wav"

install -d -m 0755 "$(dirname -- "$HOOK")"
install -d -m 0755 "$(dirname -- "$TRIGGER")"
install -d -m 0755 "$(dirname -- "$HELPER")"

install -m 0755 "$FILES_DIR/initramfs-hook" "$HOOK"
install -m 0755 "$FILES_DIR/init-premount-jingle" "$TRIGGER"
install -m 0755 "$FILES_DIR/shutdown-helper" "$HELPER"
install -m 0644 "$FILES_DIR/darkstar-shutdown-jingle.service" "$UNIT"

systemd-analyze verify "$UNIT"
systemctl daemon-reload
systemctl enable --now darkstar-shutdown-jingle.service

update-initramfs -u -k all

CURRENT_INITRD="/boot/initrd.img-$(uname -r)"
CONTENTS=$(mktemp)
lsinitramfs "$CURRENT_INITRD" > "$CONTENTS"

for REQUIRED in \
    'usr/share/darkstar/darkstar_boot.wav' \
    'scripts/init-premount/darkstar-boot-jingle' \
    'usr/bin/aplay' \
    'usr/bin/amixer'
do
    grep -Fxq "$REQUIRED" "$CONTENTS" || {
        echo "Missing from current initramfs: $REQUIRED" >&2
        rm -f -- "$CONTENTS"
        false
    }
done

rm -f -- "$CONTENTS"

echo 'Darkstar boot and shutdown jingles installed.'
echo 'Disable early boot audio with the kernel argument darkstar.audio=0.'
echo 'No EFI files or EFI variables were modified.'
