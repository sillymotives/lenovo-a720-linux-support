# Darkstar GRUB Secure Boot font verification

This note records a reproducible Secure Boot failure found while testing an owner-signed standalone GRUB image on Debian 13.

The boot chain remained valid and continued into the graphical menu, but GRUB briefly printed:

```text
error: prohibited by secure boot policy.
```

The message appeared immediately before the themed menu and disappeared within roughly one video frame.

## Symptom boundary

The following parts of the chain were already healthy:

- UEFI Secure Boot was enabled;
- the distribution shim loaded successfully;
- the standalone GRUB image carried a valid owner signature accepted through MOK;
- Linux booted with lockdown enabled;
- the embedded Darkstar PF2 fonts rendered correctly;
- the error did not prevent normal boot.

This made the message a rejected secondary file load inside GRUB rather than a rejection of the GRUB EFI executable itself.

## Misleading early candidates

Controlled test images ruled out several plausible causes:

- forcing the embedded `all_video` module did not remove the message;
- shadowing `load_env` did not remove it;
- early console marker tests were not visible reliably on this firmware;
- `sleep`, `reboot`, and `halt` canaries were invalid because the firmware/GRUB path sometimes continued into the normal configuration instead of terminating as expected.

The last point matters: an apparent second boot cannot be used as a boundary marker unless the test proves that the diagnostic image actually stopped execution.

## The generated configuration

Debian's generated `/boot/grub/grub.cfg` normally contains logic equivalent to:

```grub
if [ x$feature_default_font_path = xy ] ; then
    font=unicode
else
    font="/usr/share/grub/unicode.pf2"
fi

if loadfont $font ; then
    set gfxmode=auto
    load_video
    insmod gfxterm
fi
```

With `feature_default_font_path=y`, this executes:

```grub
loadfont unicode
```

The original standalone image embedded the four custom Darkstar fonts under explicit memdisk paths, but it did not place the stock Unicode font at GRUB's name-only bundled-font location:

```text
/fonts/unicode.pf2
```

GRUB therefore fell through to a loose on-disk font. Under Secure Boot, current Debian GRUB verifies font files and rejected that load with the generic policy message.

## Confirmed fix

Embed the distribution's stock Unicode PF2 explicitly when building the standalone image:

```bash
UNICODE_FONT=${UNICODE_FONT:-/usr/share/grub/unicode.pf2}
```

and add this `grub-mkstandalone` mapping:

```bash
"/fonts/unicode.pf2=$UNICODE_FONT" \
```

The explicit mapping is intentional even when `grub-mkstandalone` is also passed `--fonts=unicode`. The tested Debian 13 build required the file to be present at the name-only memdisk path used by `loadfont unicode`.

The repaired image grew by approximately the size of `unicode.pf2`, its signature verified, and two one-time cold boots through the test loader completed normally. After promotion to the permanent shim path, the policy message remained absent.

## Safe validation sequence

Do not promote a new signed loader directly to the permanent path.

1. Build without modifying the EFI System Partition.
2. Verify the build product with `sbverify`.
3. Copy it to a temporary `.new` name beside the test loader.
4. Compare SHA-256 hashes and bytes.
5. Verify the staged copy again.
6. Preserve the known-good test loader with a dated filename.
7. Rename `.new` atomically into the test path.
8. Use a one-time `BootNext` entry for a cold boot.
9. Repeat the cold-boot test before permanent promotion.
10. Preserve a dated rollback copy of the permanent loader.

The reusable builder in [`tools/darkstar-grub/build-standalone.sh`](../tools/darkstar-grub/build-standalone.sh) includes the trusted Unicode mapping and does not write to the ESP or EFI variables.

## Residual pre-menu flash

After the policy error was removed, a very brief blank or blue-black transition remained before the graphical menu. Frame-by-frame inspection contained no readable error text. It is consistent with a firmware, shim, or GRUB framebuffer clear or graphics-mode handoff rather than a Secure Boot rejection.

A standard 30 fps recording cannot exclude an event shorter than one frame. A higher-frame-rate recording is appropriate when distinguishing a sub-33 ms text flash from a display-mode transition.

## Menu timeout

GRUB's normal menu timeout is integer-based. The public Darkstar generator therefore uses a two-second menu rather than attempting an unreliable fractional value such as 2.5 seconds:

```grub
set timeout_style=menu
set timeout=2
```

Always modify the source generator under `/etc/grub.d` and regenerate `grub.cfg`; do not hand-edit the generated `/boot/grub/grub.cfg`.

## Publishing boundary

Do not commit any of the following while documenting or reproducing this work:

- private Secure Boot keys;
- enrolled machine certificates;
- signed machine-specific EFI binaries;
- ESP backups;
- EFI variables or Boot#### dumps;
- filesystem UUIDs;
- BIOS images;
- recovery archives or ISOs.

The diagnosis and builder change are reusable without publishing any machine secret.
