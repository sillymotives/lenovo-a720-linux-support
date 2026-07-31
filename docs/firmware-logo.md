# A720 firmware splash replacement

This documents the successful replacement of the Lenovo vendor splash inside an IdeaCentre A720 Type 2564 BIOS image.

The repository deliberately does **not** contain a BIOS dump, a prebuilt modified BIOS, NVRAM, serial numbers, UUIDs, or an OEM Windows key. Every candidate must be built from the owner's own fresh firmware read.

## Tested machine

- Lenovo IdeaCentre A720 Type 2564
- AMI Aptio-era Lenovo firmware `ERKT15AUS`
- Intel HM76 platform
- 8 MiB Winbond SPI flash
- 4 MiB host BIOS region at flash offsets `0x00400000-0x007fffff`

Other firmware revisions may use different GUIDs, layouts, image formats, or security rules. Do not assume this procedure applies to another model.

## What was found

The visible Lenovo splash is stored twice in the host BIOS region. Both copies must be replaced:

```text
4d3d82ae-2c3a-4c14-99bd-d59644ef6bc0
6c9013d0-4059-4723-af2a-05e63ffecf19
```

Each file is a RAW section nested inside a Tiano-compressed section. On the tested firmware, the original splash is:

```text
768 x 432
32 bits per pixel
BI_RGB / uncompressed
bottom-up BGRA
reserved alpha byte set to zero
```

The old UEFITool reconstruction engine and `UEFIReplace 0.28.0` successfully rebuilt both files while preserving the rest of the firmware volume.

## Safe workflow

1. Read the host BIOS region at least twice and require byte-identical results.
2. Keep one immutable golden read off the machine.
3. Convert the artwork to the exact AMI-compatible BMP format.
4. Replace both GUIDs in an offline copy.
5. Validate all firmware-volume and FFS checksums.
6. Tiano-decompress both replacement files and compare the embedded BMP byte-for-byte with the intended image.
7. Confirm that every non-logo, non-padding FFS file is unchanged.
8. Only consider writing after arranging a recovery path.
9. After writing, perform a fresh physical readback and compare it byte-for-byte with the candidate before rebooting.

The scripts in `tools/firmware-logo/` stop at read-only acquisition and
offline candidate construction. Independent firmware-volume, checksum, and
decompression validation remains mandatory. They do not contain an automatic
flash command.

## Dependencies

- Python 3
- Pillow for image conversion
- `flashrom` for read-only acquisition
- `UEFIReplace 0.28.0` from the UEFITool old engine

The build script expects `UEFIREPLACE=/path/to/UEFIReplace` unless the executable is already in `PATH`.

## Create an AMI-compatible BMP

Render or export your artwork to a 768 x 432 PNG, preferably with transparency, then run:

```bash
python3 tools/firmware-logo/make_firmware_bmp.py \
  artwork.png \
  firmware-logo.bmp
```

Transparent pixels are composited onto black. The converter writes bottom-up BGRA pixels with a zero reserved byte and the two trailing bytes observed in the original resource.

## Read the BIOS region

This is a read-only operation:

```bash
tools/firmware-logo/read_bios_region.sh ./a720-read
```

Run it twice into separate directories and compare the resulting `bios.bin` files before doing anything else.

## Build an offline candidate

```bash
UEFIREPLACE=/path/to/UEFIReplace \
  tools/firmware-logo/build_candidate.sh \
  ./a720-read/bios.bin \
  ./firmware-logo.bmp \
  ./candidate-output
```

The output directory contains the intermediate image, final candidate,
replacement logs, and hashes. Those outputs are evidence for a later
independent validation pass; they are not themselves structural validation.

## Why whole-image hashes change after boot

The beginning of the BIOS region contains writable UEFI variables. A normal boot may update NVRAM, boot counters, or settings, so a whole-region SHA-256 can change even when the static firmware volumes remain intact. Build from a fresh read and compare static regions structurally rather than assuming every post-boot whole-image hash must stay fixed.

## Warm reboot versus cold boot

On the tested A720, a warm reboot can show more than one visual stage because Plymouth, the motherboard firmware, and the display/scaler path may each draw independently. A full power-off is the cleanest way to judge the vendor splash.

## Safety

Firmware modification can leave the machine unable to boot. Internal write success does not eliminate the need for an external recovery strategy. Never distribute or publish machine-specific BIOS reads.
