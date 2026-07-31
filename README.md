# Lenovo IdeaCentre A720 reverse-engineered Linux support

This repository provides reverse-engineered Linux platform support for the Lenovo IdeaCentre A720 all-in-one PC. On a stock modern Linux installation, several A720-specific features are absent or fragile: the capacitive bezel controls cannot be handled as ordinary keys because they use a proprietary, stateful WMI protocol; the Broadcom BCM20702A1 Bluetooth adapter needs the correct firmware and integration; accelerated Nouveau/Mesa graphics and video decoding require machine-specific setup; and out-of-tree hardware support can disappear after kernel upgrades unless DKMS and initramfs are managed across retained kernels. This project turns those discoveries into guarded drivers, services, installers, diagnostics, and recovery documentation.

The capacitive volume controls were the starting point, not the limit. The project now also covers Debian audio quirks, hardware verification, sanitized boot diagnostics, Secure Boot and standalone GRUB research, ReaR recovery media, read-only firmware acquisition, offline splash-image construction, desktop fixes, and privacy-conscious system auditing.

The normal installer handles the core platform support. Bootloader, recovery, and firmware work is intentionally kept separate, documented, and conservative.

## Scope and status

### Core platform support

- Capacitive Volume Up and Volume Down: working
- Stateful Lenovo WMI handshake: reverse-engineered and implemented
- Absolute-volume bridge: working with PulseAudio and PipeWire/WirePlumber
- Persistent startup: working through DKMS and systemd
- Retained-kernel support: DKMS and initramfs integration documented and verified
- Broadcom BCM20702A1 Bluetooth firmware: documented and verified
- Nouveau/Mesa accelerated graphics: documented and verified
- Hardware verification and sanitized boot diagnostics: included

### Additional research and tooling

- Brightness-button protocol: identified, not implemented yet
- Owner-signed standalone GRUB and Secure Boot font handling: documented with reproducible tooling
- ReaR recovery-media Secure Boot layout: documented
- A720 firmware-logo workflow: limited to read-only acquisition and offline candidate construction
- Picom/Xfce desktop shutdown artefacts: documented
- Review-before-publish system inventory capture: included

## How the volume-control subsystem works

The firmware exposes two ACPI WMI GUIDs:

- `ABBC0F20-8EA1-11D1-00A0-C90629100000`: event channel
- `ABBC0F40-8EA1-11D1-00A0-C90629100000`: data and command channel

Lenovo's volume protocol is stateful:

1. Event `0x16` asks the OS to synchronize its current volume.
2. The driver sends `01 10 05 03 03 a8 VV`, where `VV` is 0 to 100.
3. Event `0x17` announces that a requested volume is available.
4. The driver sends `01 10 04 02 03 a7` and queries the WMI data block.
5. Response byte 5 contains the requested absolute volume.
6. The user-space bridge applies it with `pactl` or `wpctl`.

This is why the initial WMI event payload cannot be mapped directly to Up or Down keycodes.

## Core installer requirements

- Lenovo IdeaCentre A720
- Linux with the WMI bus driver API used by Linux 6.12
- Kernel headers for each installed kernel that should retain bezel support
- DKMS
- Python 3
- Either PulseAudio with `pactl`, or PipeWire/WirePlumber with `wpctl`
- systemd

The installer currently targets Debian-family systems and uses `apt-get`.

## Install the core support

```bash
sudo ./install.sh
```

The installer:

- installs build dependencies and available headers for installed kernels;
- builds and installs the module through DKMS for every kernel with headers;
- adds the module to initramfs-tools and refreshes matching initramfs images;
- installs tracked systemd units for the WMI handshake and audio bridge;
- waits for a usable PulseAudio or PipeWire default sink before starting the bridge;
- enables both services.

## Verify the core support

```bash
systemctl status a720-wmi-handshake.service
systemctl --user status a720-volume-bridge.service
journalctl --user -u a720-volume-bridge.service -f
```

A healthy user-service log resembles:

```text
A720 bridge ready: backend=pactl, initial volume=50%
Lenovo bezel requested 56% -> applied
```

For a broader hardware check, run:

```bash
sh tools/verify-a720-hardware.sh
```

## Retaining a fallback kernel

DKMS can only build the A720 module for kernels whose matching headers are installed. The installer attempts to install headers for every kernel under `/lib/modules` when the package is still available.

To deliberately retain a known-good fallback kernel on Debian, mark both its image and headers as manually installed:

```bash
sudo apt-mark manual \
  linux-image-<version>-amd64 \
  linux-headers-<version>-amd64
```

Verify coverage with:

```bash
sudo dkms status
lsinitramfs /boot/initrd.img-<version>-amd64 | grep a720_wmi_handshake
```

A fallback kernel without matching headers can still boot, but it will not receive rebuilt out-of-tree modules.

## Debian ALSA restore-rule workaround

Some Debian `alsa-utils` builds contain jumps to `alsa_restore_std` without defining that label. This can interfere with ALSA state restoration. An optional guarded helper is included:

```bash
sudo ./extras/debian/fix-alsa-restore-rule.sh
```

The helper refuses unknown rule layouts, copies the vendor rule into `/etc/udev/rules.d`, and corrects only the missing label. The `/etc` override survives package updates. It is intentionally not run by the main installer because it changes system-wide audio restoration behaviour.

## Additional platform support

- [`docs/bluetooth.md`](docs/bluetooth.md): BCM20702A1 firmware identity, guarded installation, OBEX integration, and BlueZ directory permissions.
- [`docs/graphics.md`](docs/graphics.md): early Nouveau loading, Mesa acceleration, video-decoder interfaces, and known firmware messages.
- [`docs/boot-warning-catalogue.md`](docs/boot-warning-catalogue.md): classification of fixed issues, expected diagnostics, firmware quirks, security notices, and third-party warnings.
- [`tools/capture-boot-audit.sh`](tools/capture-boot-audit.sh): sanitized current-boot warning capture.
- [`tools/verify-a720-hardware.sh`](tools/verify-a720-hardware.sh): checks the known Bluetooth, graphics, video, and systemd state.

The Broadcom firmware blob is not redistributed by this project. The helper accepts a lawfully obtained user-supplied file and validates its exact size and SHA-256 digest before installation.

## Experimental boot, recovery, and firmware research

The following material is separate from the normal driver installation. `install.sh` does not build firmware images, replace bootloaders, write the EFI System Partition, or modify EFI variables.

- [`tools/darkstar-grub/README.md`](tools/darkstar-grub/README.md): reproducible owner-signed standalone GRUB construction and staged validation.
- [`docs/darkstar-secure-boot-fonts.md`](docs/darkstar-secure-boot-fonts.md): diagnosis of verified-font loading under Secure Boot.
- [`docs/rear-secure-boot.md`](docs/rear-secure-boot.md): isolated stock-loader layout for ReaR recovery media.
- [`docs/firmware-logo.md`](docs/firmware-logo.md): read-only acquisition and offline A720 splash-candidate construction.
- [`docs/desktop-polish.md`](docs/desktop-polish.md): the Picom/Xfce shutdown ghost-surface fix.
- [`docs/bluetooth-and-bridges.md`](docs/bluetooth-and-bridges.md): publication and privacy boundaries for machine-state diagnostics.
- [`tools/system-inventory/capture-public-state.sh`](tools/system-inventory/capture-public-state.sh): deliberately limited review-before-publish inventory capture.

The firmware tooling stops at read-only acquisition and offline candidate construction. The standalone GRUB builder produces a local signed image only; promotion must follow the staged-copy, signature-verification, rollback, and one-time boot procedure documented in its README.

## Uninstall

```bash
sudo ./uninstall.sh
```

## Manual build

```bash
make -C src
sudo insmod src/a720_wmi_handshake.ko
```

Do not load multiple experimental A720 WMI modules simultaneously.

## Safety

The driver sends only the exact WMI commands recovered from Lenovo's original utility:

```text
01 10 05 03 03 a8 VV
01 10 04 02 03 a7
```

Do not substitute arbitrary command bytes or resume blind embedded-controller writes.

## Reverse-engineering notes

See [`docs/protocol.md`](docs/protocol.md) for the protocol and [`docs/failed-approaches.md`](docs/failed-approaches.md) for the paths that looked plausible but were wrong.

## Licence

The kernel module is licensed under GPL-2.0-only. The repository is distributed under GPL-2.0-only; see [`LICENSE`](LICENSE).

## Disclaimer

This is an independent community project and is not affiliated with or endorsed by Lenovo.
