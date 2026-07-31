# Darkstar standalone GRUB

This directory contains the reusable pieces of the signed standalone GRUB setup proven on a Lenovo IdeaCentre A720 running Debian 13 with Secure Boot enabled.

The design is:

```text
UEFI firmware
  -> Microsoft-signed Debian shim
  -> owner-signed standalone GRUB
  -> normal Debian /boot/grub/grub.cfg
```

The standalone image embeds the Darkstar theme, its four custom PF2 fonts, and the distribution Unicode font at `/fonts/unicode.pf2`. This matters because current Debian GRUB enforces verification of font files under Secure Boot. Loose fonts can be rejected, while files packed into the signed GRUB bundle are covered by the executable signature.

The Unicode path is not decorative. Debian's generated configuration commonly executes `loadfont unicode`; the tested standalone image emitted a brief `prohibited by secure boot policy` message until the stock font was explicitly mapped to GRUB's name-only bundled-font location. See [`docs/darkstar-secure-boot-fonts.md`](../../docs/darkstar-secure-boot-fonts.md) for the diagnosis and controlled test sequence.

## Deliberately not included

This repository does not contain:

- private signing keys;
- enrolled MOK certificates tied to a machine;
- prebuilt or signed EFI binaries;
- EFI variables or Boot#### records;
- filesystem UUIDs;
- ESP backups;
- BIOS images.

Generate all keys and binaries locally.

## Requirements

On Debian-family systems:

```bash
sudo apt install grub-efi-amd64-bin grub-efi-amd64-signed \
  shim-signed sbsigntool binutils fontconfig imagemagick
```

You also need an already-enrolled MOK key pair suitable for `sbsign`, plus the distribution Unicode PF2. The builder defaults to:

```text
/usr/share/grub/unicode.pf2
```

Override it with `UNICODE_FONT=/path/to/unicode.pf2` when necessary.

By default, the builder extracts the `sbat`, `grub`, and Debian-specific GRUB
rows from:

```text
/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed
```

Override that path with `SBAT_SOURCE` only when `GRUBDIR` comes from a matching
different GRUB build. The builder appends its own `grub.darkstar` row and
verifies that the embedded `.sbat` section matches the requested CSV exactly.

## Build the four Darkstar PF2 fonts

Use an ordinary installed font as the source. DejaVu Sans is used here because it is widely available and legible at 1920 x 1080.

```bash
mkdir -p fonts

grub-mkfont --name='Darkstar Title' --size=52 --range=0x20-0x7e \
  --output=fonts/title.pf2 \
  /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

grub-mkfont --name='Darkstar Menu' --size=30 --range=0x20-0x7e \
  --output=fonts/menu.pf2 \
  /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf

grub-mkfont --name='Darkstar Menu' --size=30 --range=0x20-0x7e \
  --output=fonts/menu-bold.pf2 \
  /usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf

grub-mkfont --name='Darkstar Status' --size=22 --range=0x20-0x7e \
  --output=fonts/status.pf2 \
  /usr/share/fonts/truetype/dejavu/DejaVuSans.ttf
```

Expected internal names:

```text
Darkstar Title Bold 52
Darkstar Menu Regular 30
Darkstar Menu Bold 30
Darkstar Status Regular 22
```

## Enable the conditional theme

Install the generator and regenerate the normal Debian configuration:

```bash
sudo install -m 0755 05_darkstar_theme /etc/grub.d/05_darkstar_theme
sudo update-grub
sudo grub-script-check /boot/grub/grub.cfg
```

The theme is only enabled when the standalone image exports `darkstar=1`. The stock Debian path therefore remains visually and operationally independent.

The public generator uses a two-second visible menu. GRUB's ordinary menu timeout is integer-based, so a fractional target such as 2.5 seconds is not dependable. Change the source generator and rerun `update-grub`; do not hand-edit the generated `/boot/grub/grub.cfg`.

## Build

From this directory:

```bash
ROOT_UUID=$(findmnt -no UUID /) \
SIGN_KEY=/path/to/private.key \
SIGN_CERT=/path/to/certificate.pem \
./build-standalone.sh
```

The script generates and embeds a full-screen pure-black PNG, inherits the
matching distribution SBAT rows, validates the embedded configuration and SBAT
data, places the stock Unicode font at `/fonts/unicode.pf2`, validates the
signature, and checks that the PE certificate table physically exists inside
the final file. It does not modify the ESP or EFI variables.

The output directory carries a `.darkstar-build-directory` marker. A subsequent
run may replace only a directory carrying that marker; an existing unmarked
path is refused rather than recursively removed.

## Stage before promotion

Never overwrite the live loader directly from the build directory. Copy to a temporary name on the ESP, compare hashes and bytes, and verify the staged signature first:

```bash
sudo cp build/grubx64.efi /boot/efi/EFI/darkstar-loader/grubx64.efi.new
sudo sync
sha256sum build/grubx64.efi \
  /boot/efi/EFI/darkstar-loader/grubx64.efi.new
cmp -s build/grubx64.efi \
  /boot/efi/EFI/darkstar-loader/grubx64.efi.new
sbverify --cert /path/to/certificate.pem \
  /boot/efi/EFI/darkstar-loader/grubx64.efi.new
```

Back up the known-good live image before promotion, then use a one-time `BootNext` test. Repeat the cold-boot test before moving the image into the permanent path. Keep a stock Debian shim and signed GRUB entry in the permanent boot order as the recovery route.

## Cold-boot BGRT rectangle

A graphical GRUB menu on the tested A720 briefly left a large dark rectangle visible during the handoff to the kernel. The symptom was intermittent enough that an early `GRUB_GFXPAYLOAD_LINUX="text"` test appeared to cure it, but repeated controlled cold boots disproved that explanation.

The rectangle survived all of these experiments:

- matching or removing `menu_pixmap_style`;
- embedding a full-screen dark-navy background;
- moving and shrinking the `boot_menu` component;
- switching from `gfxterm` to the firmware console immediately before `linux`;
- removing an accidentally executable backup generator from `/etc/grub.d`.

The geometry tracer was decisive: the menu moved into the lower-left corner while the rectangle remained centred. The rectangle therefore did not belong to the menu component.

The firmware exposes its splash through ACPI BGRT as an opaque 768 x 432 BMP positioned at x=576, y=196 on the 1920 x 1080 framebuffer. Its four corners are exact black, and roughly 91 percent of the image is black canvas. The original GRUB theme used `#02040a`, making the inherited `#000000` firmware canvas visible as a subtly darker rectangle.

The confirmed fix is to use exact black for every GRUB canvas surface:

```text
desktop-color: "#000000"
desktop-image: "background.png"
desktop-image-scale-method: "stretch"
message-bg-color: "#000000"
```

`build-standalone.sh` generates `background.png` as a pure-black PNG and embeds it in the signed standalone image. With that one colour match, the rectangle disappeared consistently while the normal live `/boot/grub/grub.cfg` handoff remained intact. No `bgrt_disable` kernel argument and no frozen embedded copy of the live GRUB configuration are required.

The final visually centred menu geometry used on the tested 1920 x 1080 panel is:

```text
left = 40%
top = 42%
width = 42%
height = 30%
```

The entries remain left-aligned inside that box because GRUB's theme format does not provide a separate menu-item text-alignment property.

## Important failure mode

Do not run a mutating `objcopy` command against the signed image. Authenticode data lives in a PE overlay and can be silently discarded by an in-place rewrite. Inspect sections only on disposable copies.

A truncated signed GRUB may show:

```text
Malformed security header
Failed to read headers: Invalid Parameter
Failed to load image: Invalid Parameter
```

Check whether the PE security directory ends beyond EOF:

```bash
objdump -p grubx64.efi | grep 'Security Directory'
stat -c '%s' grubx64.efi
sbverify --list grubx64.efi
```

For the stock Debian route, compare the ESP copy with the packaged image under `/usr/lib/grub/x86_64-efi-signed/` before restoring it.
