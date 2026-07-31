#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 BIOS.bin LOGO.bmp OUTPUT_DIR" >&2
    exit 2
fi

BIOS=$1
LOGO=$2
OUT=$3
UEFI=${UEFIREPLACE:-UEFIReplace}
GUID1='4d3d82ae-2c3a-4c14-99bd-d59644ef6bc0'
GUID2='6c9013d0-4059-4723-af2a-05e63ffecf19'

mkdir -m 0700 "$OUT"

[ "$(stat -c %s "$BIOS")" -eq 4194304 ] || {
    echo 'BIOS image must be exactly 4 MiB.' >&2
    exit 1
}
[ "$(stat -c %s "$LOGO")" -eq 1327160 ] || {
    echo 'Logo BMP must be exactly 1,327,160 bytes.' >&2
    exit 1
}
command -v "$UEFI" >/dev/null 2>&1 || {
    echo 'UEFIReplace 0.28.0 not found. Set UEFIREPLACE=/path/to/UEFIReplace.' >&2
    exit 1
}

cp "$BIOS" "$OUT/base-bios.bin"

"$UEFI" "$OUT/base-bios.bin" "$GUID1" 19 "$LOGO" \
    -o "$OUT/stage1.bin" | tee "$OUT/replace-guid1.log"

"$UEFI" "$OUT/stage1.bin" "$GUID2" 19 "$LOGO" \
    -o "$OUT/a720-logo-candidate.bin" | tee "$OUT/replace-guid2.log"

for image in "$OUT/base-bios.bin" "$OUT/stage1.bin" "$OUT/a720-logo-candidate.bin"; do
    [ "$(stat -c %s "$image")" -eq 4194304 ] || {
        echo "Unexpected output size: $image" >&2
        exit 1
    }
done

sha256sum \
    "$OUT/base-bios.bin" \
    "$OUT/stage1.bin" \
    "$OUT/a720-logo-candidate.bin" \
    "$LOGO" | tee "$OUT/SHA256SUMS"

echo
echo 'Offline candidate created. No firmware was written.'
echo 'Run an independent UEFI parser and Tiano round-trip validation before considering a write.'
echo "Output: $OUT"
