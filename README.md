# Lenovo IdeaCentre A720 Linux support

Reverse-engineered Linux hardware support, beginning with the capacitive volume controls on the Lenovo IdeaCentre A720 all-in-one PC.

The project reproduces the WMI handshake used by Lenovo's original Windows OSD utility and bridges the controller's absolute volume requests to PulseAudio or PipeWire.

## Status

- Volume Up: working
- Volume Down: working
- Persistent startup: working through DKMS and systemd
- PulseAudio: supported
- PipeWire/WirePlumber: supported
- Broadcom BCM20702A1 Bluetooth firmware: documented and verified
- Nouveau/Mesa accelerated graphics: documented and verified
- Brightness buttons: protocol identified, not implemented yet

## How it works

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

## Requirements

- Lenovo IdeaCentre A720
- Linux with the WMI bus driver API used by Linux 6.12
- Kernel headers for each installed kernel that should retain bezel support
- DKMS
- Python 3
- Either PulseAudio with `pactl`, or PipeWire/WirePlumber with `wpctl`
- systemd

The installer currently targets Debian-family systems and uses `apt-get`.

## Install

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

## Verify

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
