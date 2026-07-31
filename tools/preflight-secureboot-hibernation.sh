#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
#
# Read-only preflight for the A720 Secure Boot + prettyboot + hibernation work.
# This script does not mount filesystems, write block devices, alter EFI
# variables, copy to the ESP, sign binaries, or change system configuration.

set -uo pipefail
export LC_ALL=C
umask 077

EXPECTED_PRETTYBOOT_SHA256='9598d83bfc35d8b6fb4402caef32fc14184c1850ab97846c23376f1e09db7f85'
EXPECTED_DISK='/dev/sda'
EXPECTED_ESP='/dev/sda1'
EXPECTED_ROOT='/dev/sda2'
EXPECTED_OLD_SWAP='/dev/sda3'
SHRINK_BYTES=$((12 * 1024 * 1024 * 1024))

RECOVERY_ISO=${1:-${RECOVERY_ISO:-}}
CHECKSUM_FILE=${2:-${CHECKSUM_FILE:-}}
BACKUP_ARCHIVE=${3:-${BACKUP_ARCHIVE:-}}
REPORT=${REPORT:-/root/darkstar-integrated-preflight-$(date +%Y%m%d-%H%M%S).log}

FAILURES=0
WARNINGS=0
TMP=''

pass()
{
    printf 'PASS: %s\n' "$*"
}

warn()
{
    WARNINGS=$((WARNINGS + 1))
    printf 'WARN: %s\n' "$*" >&2
}

fail()
{
    FAILURES=$((FAILURES + 1))
    printf 'FAIL: %s\n' "$*" >&2
}

have()
{
    command -v "$1" >/dev/null 2>&1
}

section()
{
    printf '\n=== %s ===\n' "$*"
}

cleanup()
{
    if [ -n "${TMP:-}" ] && [ -d "$TMP" ]; then
        rm -rf -- "$TMP"
    fi
}
trap cleanup EXIT

if [ "$(id -u)" -ne 0 ]; then
    printf 'Run this script as root.\n' >&2
    exit 1
fi

TMP=$(mktemp -d)
exec > >(tee "$REPORT") 2>&1

printf 'Darkstar integrated preflight\n'
printf 'Started: %s\n' "$(date --iso-8601=seconds)"
printf 'Report:  %s\n' "$REPORT"
printf 'Mode:    READ ONLY\n'

section 'Required command inventory'
for command_name in \
    awk blockdev cmp date df find findmnt grep id lsblk mktemp openssl \
    sed sha256sum stat swapon tar tee uname
 do
    if have "$command_name"; then
        printf 'present: %s\n' "$command_name"
    else
        fail "missing required command: $command_name"
    fi
 done

for command_name in \
    apt-cache blkid dkms dpkg-query efibootmgr file git grub-script-check \
    isoinfo keyctl mokutil objcopy parted resize2fs sbverify sfdisk sgdisk \
    xorriso
 do
    if have "$command_name"; then
        printf 'optional: %s\n' "$command_name"
    else
        printf 'absent:   %s\n' "$command_name"
    fi
 done

section 'Machine and storage identity'
uname -a
lsblk -e 7 -o NAME,PATH,TRAN,RM,SIZE,TYPE,FSTYPE,LABEL,UUID,PARTUUID,MOUNTPOINTS

ROOT_SOURCE=$(findmnt -no SOURCE / 2>/dev/null || true)
ROOT_FSTYPE=$(findmnt -no FSTYPE / 2>/dev/null || true)
ESP_SOURCE=$(findmnt -no SOURCE /boot/efi 2>/dev/null || true)
ESP_FSTYPE=$(findmnt -no FSTYPE /boot/efi 2>/dev/null || true)

printf 'root source: %s\n' "$ROOT_SOURCE"
printf 'root type:   %s\n' "$ROOT_FSTYPE"
printf 'ESP source:  %s\n' "$ESP_SOURCE"
printf 'ESP type:    %s\n' "$ESP_FSTYPE"

[ "$ROOT_SOURCE" = "$EXPECTED_ROOT" ] ||
    fail "root is not $EXPECTED_ROOT"
[ "$ROOT_FSTYPE" = 'ext4' ] ||
    fail 'root filesystem is not ext4'
[ "$ESP_SOURCE" = "$EXPECTED_ESP" ] ||
    fail "ESP is not $EXPECTED_ESP"
[ "$ESP_FSTYPE" = 'vfat' ] ||
    fail 'ESP filesystem is not vfat'

for device in "$EXPECTED_DISK" "$EXPECTED_ESP" "$EXPECTED_ROOT" "$EXPECTED_OLD_SWAP"; do
    [ -e "$device" ] || fail "expected device is absent: $device"
done

if [ -b /dev/sdb ]; then
    printf '\nProtected external device detected:\n'
    lsblk -o NAME,PATH,TRAN,RM,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS /dev/sdb
    pass 'protected external device was inspected read-only'
else
    warn 'protected Kingston device is not currently attached'
fi

section 'Partition-table consistency'
if have sfdisk; then
    sfdisk --dump "$EXPECTED_DISK" || fail 'sfdisk could not read the partition table'
else
    warn 'sfdisk is unavailable'
fi

if have sgdisk; then
    if sgdisk -v "$EXPECTED_DISK"; then
        pass 'GPT verification completed'
    else
        fail 'GPT verification reported a problem'
    fi
else
    warn 'sgdisk is unavailable'
fi

if have parted; then
    parted -s "$EXPECTED_DISK" unit MiB print free ||
        fail 'parted could not read the disk geometry'
else
    warn 'parted is unavailable'
fi

section 'Offline-shrink feasibility estimate'
ROOT_BYTES=$(blockdev --getsize64 "$EXPECTED_ROOT" 2>/dev/null || printf '0')
TARGET_BYTES=$((ROOT_BYTES - SHRINK_BYTES))
printf 'current root partition bytes: %s\n' "$ROOT_BYTES"
printf 'planned shrink bytes:        %s\n' "$SHRINK_BYTES"
printf 'planned root target bytes:   %s\n' "$TARGET_BYTES"
df -B1 /

if [ "$ROOT_BYTES" -le "$SHRINK_BYTES" ]; then
    fail 'root partition is too small for the planned shrink'
elif have resize2fs; then
    RESIZE_OUTPUT=$(resize2fs -P "$EXPECTED_ROOT" 2>&1)
    RESIZE_RC=$?
    printf '%s\n' "$RESIZE_OUTPUT"

    if [ "$RESIZE_RC" -ne 0 ]; then
        warn 'resize2fs could not estimate the minimum size while root is mounted'
    else
        MIN_BLOCKS=$(printf '%s\n' "$RESIZE_OUTPUT" |
            awk '/minimum size/ { print $NF; exit }')
        BLOCK_SIZE=$(stat -fc '%S' /)

        if [ -n "$MIN_BLOCKS" ] && [ "$BLOCK_SIZE" -gt 0 ]; then
            MIN_BYTES=$((MIN_BLOCKS * BLOCK_SIZE))
            MARGIN_BYTES=$((TARGET_BYTES - MIN_BYTES))
            printf 'estimated minimum bytes:     %s\n' "$MIN_BYTES"
            printf 'estimated safety margin:     %s\n' "$MARGIN_BYTES"

            if [ "$MARGIN_BYTES" -gt $((8 * 1024 * 1024 * 1024)) ]; then
                pass 'estimated filesystem minimum leaves more than 8 GiB margin'
            else
                fail 'estimated filesystem minimum leaves insufficient margin'
            fi
        else
            warn 'could not parse the resize2fs minimum-size estimate'
        fi
    fi
else
    warn 'resize2fs is unavailable'
fi

section 'Current swap and hibernation state'
swapon --show
printf 'power states: '
cat /sys/power/state 2>/dev/null || true
printf 'disk modes:   '
cat /sys/power/disk 2>/dev/null || true
printf 'resume dev:   '
cat /sys/power/resume 2>/dev/null || true
printf 'resume offset:'
cat /sys/power/resume_offset 2>/dev/null || true

if [ -r /etc/initramfs-tools/conf.d/resume ]; then
    printf '\ninitramfs resume configuration:\n'
    cat /etc/initramfs-tools/conf.d/resume
else
    warn 'initramfs resume configuration is absent'
fi

printf '\nPersistent swap entries:\n'
awk '
    /^[[:space:]]*#/ { next }
    NF >= 3 && $3 == "swap" { print }
' /etc/fstab

if have busctl; then
    printf '\nsystemd CanHibernate: '
    busctl call \
        org.freedesktop.login1 \
        /org/freedesktop/login1 \
        org.freedesktop.login1.Manager \
        CanHibernate 2>/dev/null || true
fi

section 'Secure Boot and lockdown state'
if have mokutil; then
    mokutil --sb-state 2>&1 || true
else
    warn 'mokutil is unavailable'
fi

if [ -r /sys/kernel/security/lockdown ]; then
    cat /sys/kernel/security/lockdown
else
    warn 'kernel lockdown state file is absent'
fi

section 'EFI entries and exact prettyboot payload'
if have efibootmgr; then
    efibootmgr -v || fail 'efibootmgr could not read EFI variables'
else
    warn 'efibootmgr is unavailable'
fi

LIVE='/boot/efi/EFI/darkstar-loader/grubx64.efi'
RING='/boot/efi/EFI/darkstar-loader/grubx64.efi.ignition-ring-20260731-145126.new'
SHIM='/boot/efi/EFI/darkstar-loader/shimx64.efi'
MM='/boot/efi/EFI/darkstar-loader/mmx64.efi'

for path in "$LIVE" "$SHIM" "$MM"; do
    if [ -f "$path" ]; then
        sha256sum "$path"
    else
        fail "missing prettyboot-chain file: $path"
    fi
done

if [ -f "$LIVE" ]; then
    LIVE_SHA256=$(sha256sum "$LIVE" | awk '{ print $1 }')
    if [ "$LIVE_SHA256" = "$EXPECTED_PRETTYBOOT_SHA256" ]; then
        pass 'live prettyboot matches the physically confirmed hash'
    else
        fail "live prettyboot hash is unexpected: $LIVE_SHA256"
    fi
fi

if [ -f "$RING" ]; then
    if cmp -s "$LIVE" "$RING"; then
        pass 'live prettyboot matches the preserved ignition-ring candidate'
    else
        fail 'live prettyboot differs from the preserved ignition-ring candidate'
    fi
else
    warn 'preserved ignition-ring candidate is absent'
fi

if have sbverify; then
    if sbverify --list "$SHIM"; then
        pass 'shim has a readable EFI signature table'
    else
        fail 'shim signature table could not be read'
    fi

    if sbverify --list "$LIVE"; then
        pass 'prettyboot has a readable EFI signature table'
    else
        fail 'prettyboot signature table could not be read'
    fi
else
    warn 'sbverify is unavailable'
fi

section 'Prettyboot signer and enrolled MOK match'
if have mokutil && have openssl && have sbverify && [ -f "$LIVE" ]; then
    mkdir -p "$TMP/mok" "$TMP/pem"
    (
        cd "$TMP/mok" || exit 1
        mokutil --export >/dev/null
    )
    EXPORT_RC=$?
    MATCHED=''

    if [ "$EXPORT_RC" -ne 0 ]; then
        fail 'could not export enrolled public MOK certificates'
    else
        while IFS= read -r cert; do
            pem="$TMP/pem/$(basename -- "$cert").pem"
            if openssl x509 -inform DER -in "$cert" -out "$pem" \
                >/dev/null 2>&1 &&
               sbverify --cert "$pem" "$LIVE" >/dev/null 2>&1
            then
                MATCHED=$pem
                break
            fi
        done < <(find "$TMP/mok" -maxdepth 1 -type f -print | sort)

        if [ -n "$MATCHED" ]; then
            pass 'an enrolled MOK certificate verifies prettyboot'
            openssl x509 -in "$MATCHED" -noout \
                -subject -issuer -serial -fingerprint -sha256
        else
            fail 'no enrolled MOK certificate verifies prettyboot'
        fi
    fi
else
    warn 'MOK-to-prettyboot signer matching was skipped'
fi

section 'Prettyboot SBAT inspection'
if have objcopy && [ -f "$LIVE" ]; then
    cp --reflink=auto "$LIVE" "$TMP/grubx64.efi.inspect"
    if objcopy --dump-section ".sbat=$TMP/sbat.raw" \
        "$TMP/grubx64.efi.inspect" 2>/dev/null
    then
        tr -d '\000\r' < "$TMP/sbat.raw" > "$TMP/sbat.csv"
        cat "$TMP/sbat.csv"
        for row in '^sbat,' '^grub,' '^grub[.]debian,' '^grub[.]darkstar,'; do
            if grep -Eq "$row" "$TMP/sbat.csv"; then
                pass "SBAT row present: $row"
            else
                fail "required SBAT row absent: $row"
            fi
        done
    else
        fail 'could not extract prettyboot SBAT data from a disposable copy'
    fi
else
    warn 'SBAT inspection was skipped'
fi

section 'Kernel-policy feasibility'
CONFIG_FILE="/boot/config-$(uname -r)"
if [ -r "$CONFIG_FILE" ]; then
    grep -E \
        '^(CONFIG_(HIBERNATION|PM_DEBUG|SECURITY_LOCKDOWN_LSM|SECURITY_LOCKDOWN_LSM_EARLY|LOCK_DOWN_IN_EFI_SECURE_BOOT|LOCK_DOWN_KERNEL_FORCE_NONE|LOCK_DOWN_KERNEL_FORCE_INTEGRITY|MODULE_SIG|MODULE_SIG_ALL|MODULE_SIG_FORCE|MODULE_SIG_KEY|MODVERSIONS)=|# CONFIG_(PM_DEBUG|LOCK_DOWN_IN_EFI_SECURE_BOOT|LOCK_DOWN_KERNEL_FORCE_INTEGRITY|MODULE_SIG_FORCE) is not set)' \
        "$CONFIG_FILE" || true
else
    fail "kernel configuration is unreadable: $CONFIG_FILE"
fi

printf '\nLoaded out-of-tree module signer:\n'
if have modinfo && modinfo a720_wmi_handshake >/dev/null 2>&1; then
    modinfo -F filename a720_wmi_handshake
    modinfo -F signer a720_wmi_handshake
    modinfo -F sig_id a720_wmi_handshake
else
    warn 'a720_wmi_handshake module metadata is unavailable'
fi

if have dkms; then
    printf '\nDKMS state:\n'
    dkms status || warn 'dkms status returned an error'
else
    warn 'dkms is unavailable'
fi

printf '\nLocal DKMS key material metadata only:\n'
for path in /var/lib/dkms/mok.key /var/lib/dkms/mok.pub; do
    if [ -e "$path" ]; then
        stat -c '%n mode=%a owner=%U:%G size=%s' "$path"
    else
        printf 'absent: %s\n' "$path"
    fi
done

if [ -r /var/lib/dkms/mok.pub ]; then
    openssl x509 -inform DER -in /var/lib/dkms/mok.pub -noout \
        -subject -fingerprint -sha256 2>/dev/null ||
        warn 'could not parse /var/lib/dkms/mok.pub as a DER certificate'
fi

if have apt-cache; then
    printf '\nKernel source availability:\n'
    apt-cache policy linux-source-6.12 2>/dev/null || true
fi

printf '\nBuild dependency inventory:\n'
for package in \
    bc bison build-essential debhelper-compat dwarves fakeroot flex \
    libelf-dev libssl-dev linux-source-6.12 rsync
 do
    if have dpkg-query &&
       dpkg-query -W -f='${db:Status-Status}\n' "$package" 2>/dev/null |
       grep -qx 'installed'
    then
        printf 'installed: %s\n' "$package"
    else
        printf 'missing:   %s\n' "$package"
    fi
 done

section 'Repository reproducibility state'
REPO='/home/darkstar/src/lenovo-a720-linux-support'
if have git && [ -d "$REPO/.git" ]; then
    git -C "$REPO" status --short --branch
    git -C "$REPO" log -1 --oneline --decorate
    git -C "$REPO" diff --check || fail 'repository whitespace check failed'

    THEME="$REPO/tools/darkstar-grub/theme.txt"
    BUILDER="$REPO/tools/darkstar-grub/build-standalone.sh"

    if [ -f "$THEME" ]; then
        grep -nE '^\+ (label|boot_menu|circular_progress) \{' "$THEME" ||
            fail 'expected GRUB theme component syntax was not found'
        grep -nE 'id = "__timeout__"|ignition-center[.]png|ignition-tick[.]png' \
            "$THEME" || fail 'ignition-ring theme references are incomplete'
        pass 'tracked theme uses normal GRUB +component syntax'
    else
        fail 'tracked Darkstar theme is absent'
    fi

    if [ -f "$BUILDER" ]; then
        grep -nE 'grub-mkstandalone|--sbat=|sbsign|sbverify|ignition-center|ignition-tick' \
            "$BUILDER" || fail 'standalone builder lacks expected validation steps'
        pass 'tracked builder contains build, SBAT, ring, and signing stages'
    else
        fail 'tracked standalone builder is absent'
    fi
else
    warn 'local repository checkout is unavailable'
fi

section 'Recovery ISO checksum and boot structure'
if [ -n "$RECOVERY_ISO" ] && [ -f "$RECOVERY_ISO" ]; then
    printf 'ISO: %s\n' "$RECOVERY_ISO"
    stat -c 'size=%s modified=%y' "$RECOVERY_ISO"
    ACTUAL_ISO_SHA256=$(sha256sum "$RECOVERY_ISO" | awk '{ print $1 }')
    printf 'actual SHA-256: %s\n' "$ACTUAL_ISO_SHA256"

    if [ -n "$CHECKSUM_FILE" ] && [ -f "$CHECKSUM_FILE" ]; then
        printf 'manifest: %s\n' "$CHECKSUM_FILE"
        ISO_BASE=$(basename -- "$RECOVERY_ISO")
        EXPECTED_ISO_SHA256=$(awk -v base="$ISO_BASE" '
            $1 ~ /^[[:xdigit:]]{64}$/ {
                name=$2
                sub(/^\*/, "", name)
                sub(/^.[/]/, "", name)
                if (name == base) {
                    print tolower($1)
                    exit
                }
            }
        ' "$CHECKSUM_FILE")

        if [ -z "$EXPECTED_ISO_SHA256" ]; then
            HASH_COUNT=$(awk '$1 ~ /^[[:xdigit:]]{64}$/ { count++ } END { print count+0 }' \
                "$CHECKSUM_FILE")
            if [ "$HASH_COUNT" -eq 1 ]; then
                EXPECTED_ISO_SHA256=$(awk '$1 ~ /^[[:xdigit:]]{64}$/ { print tolower($1); exit }' \
                    "$CHECKSUM_FILE")
            fi
        fi

        if [ -z "$EXPECTED_ISO_SHA256" ]; then
            fail 'could not identify the recovery ISO hash in the manifest'
        elif [ "$EXPECTED_ISO_SHA256" = "$ACTUAL_ISO_SHA256" ]; then
            pass 'recovery ISO matches the supplied checksum manifest'
        else
            fail 'recovery ISO checksum does not match the supplied manifest'
        fi
    else
        fail 'recovery checksum manifest was not supplied'
    fi

    if have file; then
        file "$RECOVERY_ISO"
    fi

    if have xorriso; then
        if xorriso -indev "$RECOVERY_ISO" -report_el_torito plain; then
            pass 'xorriso found an El Torito boot catalog'
        else
            fail 'xorriso could not validate the ISO boot catalog'
        fi
        xorriso -indev "$RECOVERY_ISO" -pvd_info || true
    elif have isoinfo; then
        if isoinfo -d -i "$RECOVERY_ISO"; then
            pass 'isoinfo could read the ISO descriptor'
        else
            fail 'isoinfo could not read the ISO descriptor'
        fi
    else
        warn 'neither xorriso nor isoinfo is installed; boot metadata was not inspected'
    fi
else
    fail 'recovery ISO path was not supplied or does not exist'
fi

section 'ReaR backup archive integrity and contents'
if [ -n "$BACKUP_ARCHIVE" ] && [ -f "$BACKUP_ARCHIVE" ]; then
    printf 'archive: %s\n' "$BACKUP_ARCHIVE"
    stat -c 'size=%s modified=%y' "$BACKUP_ARCHIVE"

    if tar -tzf "$BACKUP_ARCHIVE" > "$TMP/archive.list"; then
        pass 'backup archive decompressed and parsed completely'
    else
        fail 'backup archive failed a complete tar listing'
    fi

    for member in \
        boot/efi/EFI/darkstar-loader/shimx64.efi \
        boot/efi/EFI/darkstar-loader/grubx64.efi \
        boot/grub/grub.cfg \
        etc/fstab \
        etc/initramfs-tools/conf.d/resume
    do
        if grep -Fxq "$member" "$TMP/archive.list"; then
            pass "backup member present: $member"
        else
            fail "backup member absent: $member"
        fi
    done

    ARCHIVE_PRETTYBOOT_SHA256=$(
        tar -xOzf "$BACKUP_ARCHIVE" \
            boot/efi/EFI/darkstar-loader/grubx64.efi 2>/dev/null |
        sha256sum |
        awk '{ print $1 }'
    )
    printf 'archived prettyboot SHA-256: %s\n' "$ARCHIVE_PRETTYBOOT_SHA256"

    if [ "$ARCHIVE_PRETTYBOOT_SHA256" = "$EXPECTED_PRETTYBOOT_SHA256" ]; then
        pass 'backup contains the physically confirmed prettyboot payload'
    else
        fail 'backup contains a different or unreadable prettyboot payload'
    fi
else
    fail 'ReaR backup archive path was not supplied or does not exist'
fi

section 'Preflight result'
printf 'Failures: %s\n' "$FAILURES"
printf 'Warnings: %s\n' "$WARNINGS"
printf 'Report:   %s\n' "$REPORT"

if [ "$FAILURES" -eq 0 ]; then
    pass 'all mandatory read-only preflight checks passed'
    exit 0
fi

printf 'STOP: do not repartition or enable Secure Boot yet.\n' >&2
exit 1
