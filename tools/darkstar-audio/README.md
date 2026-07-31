# Darkstar boot and shutdown jingles

This directory contains the reproducible audio and installation pieces for the
Darkstar boot experience proven on a Lenovo IdeaCentre A720 running Debian 13.
It adds a short ascending C-minor hardware-check jingle during the Plymouth
phase and a descending lock tone during shutdown or restart.

The boot path is deliberately independent of PulseAudio and PipeWire. The
installer embeds `aplay`, `amixer`, the generated boot WAV, and the required HDA
modules into the initramfs. At boot, the trigger resolves the internal PCH HDA
card, creates a minimal temporary ALSA configuration that points directly at
`hw:<card>,0`, sets the tested A720 speaker controls, and plays the native
48 kHz stereo 16-bit WAV.

The minimal configuration matters. Copying the desktop ALSA configuration into
the initramfs can pull in PulseAudio plugin references that are unavailable in
early userspace. The trigger also uses BusyBox-compatible `timeout -s TERM`
syntax because initramfs-tools commonly supplies the BusyBox implementation.

## Requirements

- Debian-family system with initramfs-tools
- Plymouth
- systemd
- Python 3
- alsa-utils
- internal Intel PCH HDA audio with the A720 ALC272 codec

## Install

```bash
sudo ./install.sh
```

The installer regenerates the WAV files from source, installs the early-boot
hook and trigger, installs the shutdown service, rebuilds all existing
initramfs images, and verifies that the active image contains the boot audio.
It does not write the EFI System Partition or modify EFI variables.

## Verify

After rebooting:

```bash
journalctl -b -k --no-pager | grep darkstar-boot-jingle
```

A successful boot ends with:

```text
darkstar-boot-jingle: PCH resolved as card 0
darkstar-boot-jingle: playback attempt 1 starting
darkstar-boot-jingle: playback complete
```

Add `darkstar.audio=0` to the kernel command line to suppress the early boot
jingle without uninstalling it.

## Generate the WAV files only

```bash
python3 generate-jingles.py --output-dir build
```

The generator creates:

- `darkstar_boot.wav`: C4, E-flat4, G4
- `darkstar_shutdown.wav`: G4, E-flat4, then a curved C4-to-90-Hz drop

Both files are stereo, 48 kHz, and 16-bit. The rounded square waveform keeps the
retro firmware character while avoiding the most abrasive edge of a hard
square wave.

## Uninstall

```bash
sudo ./uninstall.sh
```

The uninstaller removes only the Darkstar audio files and rebuilds the existing
initramfs images. It does not touch GRUB, signed EFI payloads, the permanent boot
order, firmware, or recovery media.
