# Bluetooth, audio bridges, and machine-specific Linux state

The A720 work is more than a kernel module. The useful public parts include the WMI handshake, the user-space absolute-volume bridge, systemd integration, audio-backend detection, and any reproducible Bluetooth or power-management configuration.

This page separates material that is safe to publish from machine identity and pairing secrets that must stay private.

## Existing custom bridge architecture

The repository already contains the two main pieces used for the capacitive volume controls:

1. A kernel-side WMI handshake driver receives Lenovo firmware events and exchanges the exact protocol messages recovered from the Windows utility.
2. A per-user bridge applies the requested absolute volume using either `pactl` or `wpctl`.

The split is intentional. Firmware communication stays in the smallest possible privileged component, while desktop audio control remains in user space.

Useful files to preserve publicly include:

- kernel module source and DKMS configuration;
- system and user systemd units;
- installer and uninstaller scripts;
- audio-backend selection logic;
- protocol documentation and failed approaches;
- logs with names, addresses, serials, and UUIDs removed.

## Bluetooth material worth publishing

Bluetooth fixes are most useful when they are reproducible and narrowly scoped. Good public artefacts include:

- the adapter's USB or PCI identifier;
- kernel driver and firmware package names;
- BlueZ version;
- relevant settings from `/etc/bluetooth/main.conf`;
- relevant files from `/etc/modprobe.d/`;
- udev rules created specifically for the adapter;
- systemd units or drop-ins used to recover, unblock, or power-manage it;
- exact commands used to diagnose the adapter;
- a short explanation of the original symptom and the confirmed fix.

Do not publish the contents of `/var/lib/bluetooth`. That directory can contain link keys, identity resolving keys, device names, addresses, and pairing state.

Also remove or redact:

- Bluetooth and Wi-Fi MAC addresses;
- hostnames and usernames;
- machine serial numbers and UUIDs;
- Wi-Fi SSIDs and credentials;
- private keys, certificates, MOK material, and Secure Boot signing keys;
- journal excerpts containing personal device names.

## Capturing a safe report

Run:

```bash
tools/system-inventory/capture-public-state.sh
```

The script creates a timestamped directory containing a deliberately limited and redacted snapshot of:

- OS and kernel versions;
- PCI and USB hardware IDs;
- Bluetooth controller state;
- rfkill state;
- DKMS modules;
- relevant systemd units;
- selected Bluetooth, modprobe, GRUB, and A720 service configuration;
- PipeWire, WirePlumber, or PulseAudio status where available.

It never reads `/var/lib/bluetooth`, NetworkManager connection profiles, browser data, SSH keys, or firmware images.

Review every generated file before committing it. Automated redaction is a seat belt, not a force field.

## Recommended documentation format

For each fix, record:

```text
Symptom:
Hardware ID:
Kernel and BlueZ versions:
Failed approaches:
Working configuration:
Why it works:
How to undo it:
Known limitations:
```

That structure makes the repository useful to another A720 owner instead of becoming a cryptic pile of incantations.
