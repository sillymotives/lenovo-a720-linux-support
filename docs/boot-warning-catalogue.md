# Boot warning catalogue

This catalogue records warnings observed on a Debian 13 Lenovo IdeaCentre A720 and separates actual faults from expected diagnostics, firmware quirks, third-party software noise, and security-policy choices.

The reference audit on 2026-07-31 reported zero failed system units and zero failed user units.

## Fixed or addressed

| Message or symptom | Status | Resolution |
| --- | --- | --- |
| Broadcom BCM20702A1 patch missing | Fixed | Installed `BCM20702A1-0489-e042.hcd`; the kernel confirms that the patch is loaded. |
| OBEX cannot find Evolution source registry | Fixed | Installed `evolution-data-server`; both user services run. |
| BlueZ configuration directory mode mismatch | Fixed | Added `ConfigurationDirectoryMode=0755` drop-in while preserving `/var/lib/bluetooth` at `0700`. |
| NetworkManager wait-online delays graphical boot | Fixed | `NetworkManager-wait-online.service` is masked and inactive on the reference desktop. |
| Legacy `networking.service` duplicates NetworkManager | Fixed | Disabled and inactive on the reference desktop. |
| A720 bridge starts before an audio sink exists | Fixed | User unit waits for an actual PulseAudio or PipeWire default sink. |
| Retained kernel lacks the A720 DKMS module | Fixed | Installer builds kernels with headers and refreshes matching initramfs images. |
| ALSA restore rule jumps to a missing label | Fixed | Optional guarded Debian helper creates a local corrected override. |
| Nouveau availability during early boot | Fixed | Added `nouveau` to `/etc/initramfs-tools/modules` and refreshed initramfs. |

## Expected diagnostics

### Out-of-tree module taint

```text
a720_wmi_handshake: loading out-of-tree module taints kernel
```

Expected for a module not shipped in the upstream kernel tree. It does not mean the module failed to load.

### Energy performance bias

```text
ENERGY_PERF_BIAS: Set to 'normal', was 'performance'
```

A power-policy notice rather than a boot failure.

### MXM firmware discovery

```text
MXM: GUID detected in BIOS
```

Hardware discovery information.

### Device Mapper IMA notice

```text
device-mapper: core: CONFIG_IMA_DISABLE_HTABLE is disabled
```

Relevant to specialised Integrity Measurement Architecture auditing, not ordinary desktop startup.

## Firmware and old-platform quirks

These have been observed without failed units or loss of the corresponding core desktop function:

- ACPI cannot resolve `SGST`, causing `HDSM` and `_DSM` methods to abort.
- ACPI PMIO and GPIO SystemIO regions overlap firmware OpRegions.
- `lpc_ich` reports a GPIO resource conflict.
- Realtek `r8169` cannot disable ASPM because the OS lacks firmware control.
- Nouveau reports `failed to create ce channel, -22` while direct rendering and accelerated Mesa remain available.
- `at24` cannot find a described VCC supply and uses a dummy regulator.

Do not apply DSDT overrides, disable ACPI, or change PCIe policy merely to silence these lines. Investigate only when a matching device function is actually broken.

## Security posture

### MDS

The reference system reports:

```text
Mitigation: Clear CPU buffers; SMT vulnerable
```

Mitigation is active, but simultaneous multithreading leaves residual exposure. Disabling SMT is a security-versus-performance decision, not a generic hardware-support requirement.

### VMSCAPE

The reference system reports:

```text
Mitigation: IBPB before exit to userspace
```

The kernel is applying its reported mitigation.

## Peripheral and driver noise

### Logitech HID++ protocol probe

```text
hidpp_root_get_protocol_version: received protocol error 0x08
```

Observed during startup and reconnects. Treat it as significant only when the corresponding Logitech device fails to connect or operate.

### Wi-Fi signal monitoring

```text
bgscan simple: Failed to enable signal strength monitoring
```

The requested background-scan facility is unavailable. A working network connection can coexist with this warning.

### Wireless Extensions deprecation

A process may still use Wireless Extensions and trigger a warning that they will not work with future Wi-Fi 7 hardware. This is an application compatibility warning, not an A720 failure.

### WirePlumber and UPower

WirePlumber may query UPower before it owns its D-Bus name. A one-time startup warning is benign when the audio graph subsequently works.

### Integrated camera skipped by libcamera monitor

WirePlumber may skip the A720 camera in its libcamera monitor. This is separate from audio and should be investigated only when camera use is required.

## Third-party software

The reference machine's Surfshark installation produces several warnings unrelated to Lenovo hardware support:

- deprecated systemd SysV-generator compatibility for two init scripts;
- a user service declaring IP firewall rules without root privileges;
- missing GNOME Session Manager and MATE Screensaver D-Bus services on XFCE;
- IPv6 policy-route failures in a private routing table.

Keep vendor VPN workarounds outside the A720 hardware installer.

## GNOME Keyring duplicate registration

Only one keyring daemon is running on the reference system, but a client later asks it to register the same login item repeatedly:

```text
asked to register item ... but it's already registered
```

This is not evidence of duplicate daemon startup. It remains an application-level warning unless secret storage stops working.

## Auditing

Capture a sanitized current-boot report with:

```bash
./tools/capture-boot-audit.sh
```

Review any report before publishing it. Journals can contain device identifiers, network information, usernames, and third-party application details.
