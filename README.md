# Lenovo IdeaCentre A720 Linux bezel controls

Reverse-engineered Linux support for the capacitive volume controls on the Lenovo IdeaCentre A720 all-in-one PC.

The project reproduces the WMI handshake used by Lenovo's original Windows OSD utility and bridges the controller's absolute volume requests to PulseAudio or PipeWire.

## Status

- Volume Up: working
- Volume Down: working
- Persistent startup: working through DKMS and systemd
- PulseAudio: supported
- PipeWire/WirePlumber: supported
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
- Kernel headers for the running kernel
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

- installs build dependencies;
- builds and installs the module through DKMS;
- creates a system service for the WMI handshake;
- installs a per-user audio bridge;
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
