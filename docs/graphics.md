# Graphics support

The reference Lenovo IdeaCentre A720 uses an NVIDIA GPU exposed by Mesa as `NVC1`. The working configuration uses the open-source Nouveau kernel driver and Mesa userspace drivers.

## Early driver loading

Add Nouveau to initramfs-tools so the driver is available during the early graphics handoff:

```bash
printf '%s\n' nouveau | sudo tee -a /etc/initramfs-tools/modules
sudo update-initramfs -u -k all
```

Do not add a duplicate line. Verify with:

```bash
grep -n '^nouveau$' /etc/initramfs-tools/modules
```

## 3D acceleration

Verify direct rendering and the active renderer:

```bash
glxinfo -B | grep -E 'direct rendering|Accelerated|OpenGL vendor|OpenGL renderer'
```

The tested machine reports:

```text
direct rendering: Yes
Accelerated: yes
OpenGL vendor string: Mesa
OpenGL renderer string: NVC1
```

## Video decoding

The tested system exposes VDPAU decoder profiles for MPEG-1/2, H.264 through High Profile level 4.1, VC-1, and MPEG-4 Part 2. VA-API exposes MPEG-2, VC-1, and H.264 VLD entry points.

Inspect the advertised capabilities with:

```bash
vdpauinfo
vainfo
```

HEVC, VP9, and AV1 decoding are not exposed on this hardware. Advertised profiles show that the driver stack offers those interfaces, but an actual playback test is still the best confirmation that a particular application is using hardware decoding.

## Known boot messages

The following message has been observed on this platform alongside a functioning framebuffer, direct rendering, and accelerated Mesa renderer:

```text
nouveau 0000:01:00.0: drm: failed to create ce channel, -22
```

Do not treat that line alone as proof that graphics acceleration failed. Use `glxinfo`, `vdpauinfo`, `vainfo`, and application playback logs to judge the working state.

The Lenovo firmware also emits ACPI errors involving `SGST`, `HDSM`, and `_DSM`. These originate in the machine firmware tables and have not prevented the tested Nouveau configuration from working. Avoid DSDT overrides solely to silence the messages.
