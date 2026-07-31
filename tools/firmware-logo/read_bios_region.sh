#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
set -Eeuo pipefail

export PATH=/usr/sbin:/usr/bin:/sbin:/bin

if [ "$(id -u)" -eq 0 ]; then
    echo 'Run as a regular user; this script invokes sudo only for flashrom.' >&2
    exit 1
fi

OWNER=$(id -un)
GROUP=$(id -gn)
OUT=${1:-"./a720-bios-read-$(date +%Y%m%d-%H%M%S)"}
CHIP='W25Q64BV/W25Q64CV/W25Q64FV'

mkdir -m 0700 "$OUT"

sudo -v
sudo flashrom \
    -p internal \
    -c "$CHIP" \
    --ifd \
    -i "bios:$OUT/bios.bin" \
    -r "$OUT/container.bin" \
    -o "$OUT/flashrom-read.log"

sudo chown -R "$OWNER:$GROUP" "$OUT"

if [ "$(stat -c %s "$OUT/bios.bin")" -ne 4194304 ]; then
    echo 'The BIOS region is not exactly 4 MiB.' >&2
    exit 1
fi

sha256sum "$OUT/bios.bin" "$OUT/container.bin" | tee "$OUT/SHA256SUMS"

echo
echo 'Read completed. No firmware was written.'
echo "Output: $OUT"
