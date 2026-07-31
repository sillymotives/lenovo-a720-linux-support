#!/bin/sh
# SPDX-License-Identifier: GPL-2.0-only
set -eu

umask 077

# Build a standalone x86_64-efi GRUB image with embedded Darkstar fonts and
# theme, then sign it with an already-enrolled Secure Boot key.
#
# Required environment variables:
#   ROOT_UUID   UUID of the Linux root filesystem containing /boot/grub
#   SIGN_KEY    PEM private key used by sbsign
#   SIGN_CERT   PEM certificate matching the enrolled MOK
#
# Optional environment variables:
#   BUILD          output directory, default: ./build
#   FONTDIR        PF2 input directory, default: ./fonts
#   GRUBDIR        GRUB module directory, default: /usr/lib/grub/x86_64-efi
#   UNICODE_FONT   trusted GRUB Unicode PF2, default: /usr/share/grub/unicode.pf2
#   SBAT_SOURCE    distribution-signed GRUB used as the SBAT source

: "${ROOT_UUID:?set ROOT_UUID to the root filesystem UUID}"
: "${SIGN_KEY:?set SIGN_KEY to the Secure Boot private key path}"
: "${SIGN_CERT:?set SIGN_CERT to the matching PEM certificate path}"

BUILD=${BUILD:-./build}
FONTDIR=${FONTDIR:-./fonts}
GRUBDIR=${GRUBDIR:-/usr/lib/grub/x86_64-efi}
THEME=${THEME:-./theme.txt}
UNICODE_FONT=${UNICODE_FONT:-/usr/share/grub/unicode.pf2}
SBAT_SOURCE=${SBAT_SOURCE:-/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed}
BUILD_MARKER=.darkstar-build-directory

TITLE_FONT="$FONTDIR/title.pf2"
MENU_FONT="$FONTDIR/menu.pf2"
MENU_BOLD_FONT="$FONTDIR/menu-bold.pf2"
STATUS_FONT="$FONTDIR/status.pf2"

case "$ROOT_UUID" in
    ''|*[!A-Za-z0-9._-]*)
        echo 'ROOT_UUID contains characters unsafe for GRUB configuration.' >&2
        false
        ;;
esac

case "$BUILD" in
    ''|/|.|..)
        echo "Refusing dangerous build path: $BUILD" >&2
        false
        ;;
esac

if [ -e "$BUILD" ]; then
    if [ ! -d "$BUILD" ] ||
       [ ! -f "$BUILD/$BUILD_MARKER" ] ||
       [ -L "$BUILD/$BUILD_MARKER" ]; then
        echo "Refusing to remove unmarked build path: $BUILD" >&2
        false
    fi
fi

for command in grub-mkstandalone grub-script-check sbsign sbverify objcopy objdump sha256sum magick cmp grep awk tr stat file; do
    command -v "$command" >/dev/null 2>&1 || {
        echo "Missing required command: $command" >&2
        exit 1
    }
done

for path in "$TITLE_FONT" "$MENU_FONT" "$MENU_BOLD_FONT" "$STATUS_FONT" \
            "$UNICODE_FONT" "$THEME" "$SIGN_KEY" "$SIGN_CERT" \
            "$SBAT_SOURCE" /boot/grub/grub.cfg; do
    [ -f "$path" ] || {
        echo "Missing required file: $path" >&2
        exit 1
    }
done

if [ -e "$BUILD" ]; then
    rm -rf -- "$BUILD"
fi

install -d -m 0700 -- "$BUILD"
: > "$BUILD/$BUILD_MARKER"

# Inherit the SBAT rows from the installed distribution-signed GRUB. This
# preserves the generic and Debian-specific security generations that apply
# to the patched modules used by grub-mkstandalone.
cp "$SBAT_SOURCE" "$BUILD/distribution-grub.efi.inspect"
objcopy --dump-section ".sbat=$BUILD/distribution.sbat.raw" \
    "$BUILD/distribution-grub.efi.inspect"
rm -f "$BUILD/distribution-grub.efi.inspect"
tr -d '\000\r' \
    < "$BUILD/distribution.sbat.raw" \
    > "$BUILD/distribution.sbat.csv"

awk -F, '
    $1 == "sbat" || $1 ~ /^grub([.]|$)/ { print }
' "$BUILD/distribution.sbat.csv" > "$BUILD/sbat.csv"

for required_sbat_entry in \
    '^sbat,' \
    '^grub,' \
    '^grub[.]debian,'
do
    if ! grep -Eq "$required_sbat_entry" "$BUILD/sbat.csv"; then
        echo "Required distribution SBAT row is absent: $required_sbat_entry" >&2
        false
    fi
done

if grep -Eq '^grub[.]darkstar,' "$BUILD/sbat.csv"; then
    echo 'The distribution SBAT unexpectedly contains grub.darkstar.' >&2
    false
fi

GRUB_VERSION=$(grub-mkstandalone --version | awk '{print $NF}')

case "$GRUB_VERSION" in
    ''|*,*|*[!A-Za-z0-9._+~:-]*)
        echo "Unsafe GRUB version string: $GRUB_VERSION" >&2
        false
        ;;
esac

printf 'grub.darkstar,1,Darkstar,grub2,%s,%s\n' \
    "$GRUB_VERSION" \
    'https://github.com/sillymotives/lenovo-a720-linux-support' \
    >> "$BUILD/sbat.csv"

# The A720 firmware splash is an opaque 768 x 432 BGRT bitmap whose unused
# canvas is exact black. A full-screen black GRUB background prevents that
# firmware canvas from appearing as a dark rectangle during handoff.
magick -size 64x64 xc:'#000000' "PNG24:$BUILD/background.png"

# Generate the graphical timeout assets during each reproducible build.
# The circular indicator uses a small central ignition core and cyan dots.
magick -size 36x36 xc:none \
    -fill '#ff58ff' \
    -stroke '#7af6ff' \
    -strokewidth 2 \
    -draw 'circle 18,18 18,8' \
    "PNG32:$BUILD/ignition-center.png"

magick -size 10x10 xc:none \
    -fill '#7af6ff' \
    -draw 'circle 5,5 5,1' \
    "PNG32:$BUILD/ignition-tick.png"

cat > "$BUILD/grub.cfg" <<EOF
search --fs-uuid --set=root $ROOT_UUID
set prefix=(\$root)/boot/grub

loadfont (memdisk)/boot/grub/fonts/darkstar-title.pf2
loadfont (memdisk)/boot/grub/fonts/darkstar-menu.pf2
loadfont (memdisk)/boot/grub/fonts/darkstar-menu-bold.pf2
loadfont (memdisk)/boot/grub/fonts/darkstar-status.pf2

set darkstar=1
export darkstar

if [ -f \$prefix/grub.cfg ]; then
    configfile \$prefix/grub.cfg
fi

echo "Darkstar could not find \$prefix/grub.cfg"
sleep 10
EOF

grub-script-check "$BUILD/grub.cfg"

modules='all_video bitmap bitmap_scale bli boot cat chain configfile echo efifwsetup efi_gop efi_uga ext2 fat font gettext gfxmenu gfxterm gfxterm_background gzio halt jpeg linux loadenv normal part_gpt part_msdos png reboot search search_fs_file search_fs_uuid search_label sleep test video video_bochs video_cirrus'

available=""
for module in $modules; do
    if [ -f "$GRUBDIR/$module.mod" ]; then
        available="$available $module"
    fi
done

grub-mkstandalone \
    --format=x86_64-efi \
    --output="$BUILD/grubx64.efi.unsigned" \
    --sbat="$BUILD/sbat.csv" \
    --fonts=unicode \
    --install-modules="$available" \
    --modules="$available" \
    "/boot/grub/grub.cfg=$BUILD/grub.cfg" \
    "/boot/grub/themes/darkstar/theme.txt=$THEME" \
    "/boot/grub/themes/darkstar/background.png=$BUILD/background.png" \
    "/boot/grub/themes/darkstar/ignition-center.png=$BUILD/ignition-center.png" \
    "/boot/grub/themes/darkstar/ignition-tick.png=$BUILD/ignition-tick.png" \
    "/fonts/unicode.pf2=$UNICODE_FONT" \
    "/boot/grub/fonts/darkstar-title.pf2=$TITLE_FONT" \
    "/boot/grub/fonts/darkstar-menu.pf2=$MENU_FONT" \
    "/boot/grub/fonts/darkstar-menu-bold.pf2=$MENU_BOLD_FONT" \
    "/boot/grub/fonts/darkstar-status.pf2=$STATUS_FONT"

# Debian's generated grub.cfg normally runs `loadfont unicode`. Under Secure
# Boot, a fallback to the loose on-disk font can be rejected by GRUB's file
# verifier. The explicit /fonts/unicode.pf2 mapping above places the stock font
# at the name-only memdisk path GRUB checks inside the signed image.

# Inspect SBAT only on a disposable copy. Running objcopy in-place on the
# signed image can strip the Authenticode overlay.
cp "$BUILD/grubx64.efi.unsigned" "$BUILD/grubx64.efi.inspect"
objcopy --dump-section ".sbat=$BUILD/unsigned.sbat.raw" \
    "$BUILD/grubx64.efi.inspect"
rm -f "$BUILD/grubx64.efi.inspect"
tr -d '\000\r' \
    < "$BUILD/unsigned.sbat.raw" \
    > "$BUILD/unsigned.sbat.csv"

if ! cmp -s "$BUILD/sbat.csv" "$BUILD/unsigned.sbat.csv"; then
    echo 'Embedded SBAT data does not match the requested SBAT data.' >&2
    false
fi

sbsign \
    --key "$SIGN_KEY" \
    --cert "$SIGN_CERT" \
    --output="$BUILD/grubx64.efi" \
    "$BUILD/grubx64.efi.unsigned"

sbverify --list "$BUILD/grubx64.efi"
sbverify --cert "$SIGN_CERT" "$BUILD/grubx64.efi"

set -- $(objdump -p "$BUILD/grubx64.efi" |
    awk '/Security Directory/ { print $3, $4; exit }')

[ "$#" -eq 2 ] || {
    echo "Could not read PE Security Directory" >&2
    exit 1
}

offset=$((0x$1))
size=$((0x$2))
end=$((offset + size))
file_size=$(stat -c '%s' "$BUILD/grubx64.efi")

[ "$size" -gt 0 ] && [ "$end" -le "$file_size" ] || {
    echo "PE signature table is missing or extends beyond EOF" >&2
    exit 1
}

printf '\nSigned image:\n'
file "$BUILD/grubx64.efi"
sha256sum "$BUILD/grubx64.efi.unsigned" "$BUILD/grubx64.efi"
printf 'Certificate offset: %s\n' "$offset"
printf 'Certificate size:   %s\n' "$size"
printf 'Certificate end:    %s\n' "$end"
printf 'File size:          %s\n' "$file_size"
printf '\nNo EFI System Partition files or EFI variables were changed.\n'
