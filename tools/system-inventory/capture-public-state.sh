#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Create a deliberately limited, review-before-publish A720 diagnostic bundle.
set -Eeuo pipefail

export PATH=/usr/sbin:/usr/bin:/sbin:/bin
umask 077

OUT=${1:-"./a720-public-state-$(date +%Y%m%d-%H%M%S)"}

if [ -e "$OUT" ]; then
    echo "Output path already exists; refusing to reuse it: $OUT" >&2
    false
fi

mkdir -m 0700 -- "$OUT"

redact() {
    local hostname_value
    hostname_value=$(hostname 2>/dev/null || true)
    sed -E \
        -e 's/([[:xdigit:]]{2}:){5}[[:xdigit:]]{2}/<MAC-REDACTED>/g' \
        -e 's/((PART)?UUID=)[[:alnum:]._-]+/\1<REDACTED>/g' \
        -e 's/[[:alnum:]_.-]+@[[:alnum:]_.-]+/<USER-HOST-REDACTED>/g' \
        -e 's/(Serial Number:|Serial:|UUID:)[[:space:]]*[^[:space:]]+/\1 <REDACTED>/Ig' \
        -e "s#${HOME//\//\/}#<HOME>#g" \
        -e "s#${hostname_value//\//\/}#<HOSTNAME>#g"
}

capture() {
    local name=$1
    shift
    {
        printf '$'
        printf ' %q' "$@"
        printf '\n\n'
        "$@" 2>&1 || true
    } | redact >"$OUT/$name.txt"
}

capture os-release sh -c 'cat /etc/os-release; printf "\nKernel: "; uname -a'
capture pci lspci -nnk
capture usb lsusb
capture rfkill rfkill list
capture bluetooth-version bluetoothd --version
capture bluetooth-show bluetoothctl show
capture dkms dkms status
capture modules lsmod
capture system-failures systemctl --failed --no-pager
capture user-failures systemctl --user --failed --no-pager
capture audio-status sh -c '
    command -v pactl >/dev/null && pactl info
    command -v wpctl >/dev/null && wpctl status
    command -v pipewire >/dev/null && pipewire --version
    command -v wireplumber >/dev/null && wireplumber --version
'

copy_safe_file() {
    local source=$1
    local destination=$2
    if [ -f "$source" ]; then
        redact <"$source" >"$OUT/$destination"
    fi
}

copy_matching_files() {
    local root=$1
    local prefix=$2
    [ -d "$root" ] || return 0
    while IFS= read -r -d '' file; do
        relative=${file#"$root"/}
        relative=${relative//\//__}
        redact <"$file" >"$OUT/${prefix}__${relative}"
    done < <(
        find "$root" -maxdepth 3 -type f \
            \( -iname '*a720*' -o -iname '*bluetooth*' -o -iname '*pipewire*' -o -iname '*wireplumber*' \) \
            -print0 2>/dev/null
    )
}

copy_safe_file /etc/bluetooth/main.conf bluetooth-main.conf
copy_safe_file /etc/default/grub grub-default.txt
copy_matching_files /etc/modprobe.d modprobe
copy_matching_files /etc/udev/rules.d udev
copy_matching_files /etc/systemd/system systemd-system
copy_matching_files "$HOME/.config/systemd/user" systemd-user

cat >"$OUT/REVIEW-BEFORE-PUBLISHING.txt" <<'EOF'
Review every file manually before publishing.

This script intentionally does not read:
- /var/lib/bluetooth
- NetworkManager connection profiles
- SSH or GPG keys
- Secure Boot or MOK private keys
- browser profiles
- BIOS or firmware dumps

Delete anything containing personal device names, addresses, usernames,
serial numbers, UUIDs, credentials, tokens, or unrelated local services.
EOF

printf 'Public-state capture created at: %s\n' "$OUT"
printf 'Review it manually before adding any files to Git.\n'
