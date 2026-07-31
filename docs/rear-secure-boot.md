# ReaR recovery media with Secure Boot

This note documents a conservative way to give Relax-and-Recover (ReaR) a predictable Secure Boot chain without coupling recovery media to a customised live GRUB image.

## Why pin the loader

ReaR can autodetect a shim and an adjacent GRUB EFI binary from the EFI System Partition. That is convenient, but an ESP containing timestamped backups or retired loader directories may offer several plausible pairs. Autodetection can therefore select a historical loader that was never intended for new recovery media.

The backup archive may still be healthy, but recovery boot provenance becomes needlessly ambiguous.

## Dedicated recovery layout

Keep a stock, recovery-only pair in its own directory:

```text
/boot/efi/EFI/rear/
├── shimx64.efi
├── grubx64.efi
└── mmx64.efi
```

Use:

- the distribution-provided shim;
- the distribution-signed GRUB EFI binary from the installed package;
- MokManager from the same distribution, where available.

On Debian 13, the packaged GRUB binary is normally:

```text
/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed
```

Do **not** use a customised standalone GRUB as ReaR's second stage. Its embedded configuration may be tailored to the installed system, while ReaR generates a recovery-specific `grub.cfg` that loads the recovery kernel and initramfs from the ISO.

## Stage and verify

Create the directory, copy to temporary names, verify the copies, then rename them into place. Preserve Authenticode data by copying the files byte-for-byte. Do not process signed EFI files through a mutating `objcopy` command.

A typical verification pass is:

```bash
sudo sbverify --list /boot/efi/EFI/rear/shimx64.efi
sudo sbverify --list /boot/efi/EFI/rear/grubx64.efi
sudo sbverify --list /boot/efi/EFI/rear/mmx64.efi

sha256sum \
  /boot/efi/EFI/rear/shimx64.efi \
  /boot/efi/EFI/rear/grubx64.efi \
  /boot/efi/EFI/rear/mmx64.efi
```

Compare the staged GRUB byte-for-byte with the packaged signed source:

```bash
cmp -s \
  /usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed \
  /boot/efi/EFI/rear/grubx64.efi
```

## Pin ReaR to the dedicated shim

Add this to `/etc/rear/local.conf`:

```bash
SECURE_BOOT_BOOTLOADER="/boot/efi/EFI/rear/shimx64.efi"
```

Back up the configuration before editing and check its shell syntax afterward:

```bash
sudo cp -a /etc/rear/local.conf \
  "/etc/rear/local.conf.before-rear-loader-$(date +%Y%m%d-%H%M%S)"

sudo bash -n /etc/rear/local.conf
```

When building the ISO, ReaR uses the configured shim as the removable-media `BOOTX64.efi`, takes the adjacent `grubx64.efi` as the second stage, and supplies its own recovery configuration.

## Confirm the resulting backup

A verbose ReaR run should identify the dedicated pair explicitly:

```text
Using '/boot/efi/EFI/rear/shimx64.efi' as UEFI Secure Boot bootloader file
Using Shim '/boot/efi/EFI/rear/shimx64.efi' as first stage UEFI bootloader BOOTX64.efi
Using second stage UEFI bootloader files for Shim: /boot/efi/EFI/rear/grubx64.efi
```

After the run:

1. verify the complete backup archive;
2. calculate and recheck SHA-256 sums for both the archive and recovery ISO;
3. flush pending writes and cleanly unmount the backup device;
4. retain the full ReaR log beside the backup;
5. boot-test the recovery ISO using separate disposable media or another safe test method.

## What must stay private

Do not publish:

- backup archives or recovery ISOs containing personal files;
- filesystem UUIDs or EFI-variable dumps;
- ESP backups;
- enrolled certificates tied to a particular machine;
- private Secure Boot signing keys;
- machine-specific signed EFI binaries.

This repository documents the layout and procedure only. Every recovery image must be generated and verified locally.
