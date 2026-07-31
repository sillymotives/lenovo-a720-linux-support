# Bluetooth support

The Lenovo IdeaCentre A720 tested for this project contains a Broadcom BCM20702A1 USB controller with USB ID `0489:e042`.

## Firmware

Linux requests the following patch file when the controller is detected:

```text
/usr/lib/firmware/brcm/BCM20702A1-0489-e042.hcd
```

The file verified on the reference machine has these properties:

```text
size:   34904 bytes
sha256: 9372ce8bfe400ef4560ca550007bd4bdf97b8b5ec70d24a45aa977050b6d8e4a
```

The firmware blob is not included in this repository. The known copy is covered by Broadcom's WIDCOMM licence, which does not provide a clear general redistribution grant. Obtain the firmware from a source you are licensed to use, then install it with the guarded helper:

```bash
sudo ./extras/debian/install-bcm20702a1-firmware.sh /path/to/BCM20702A1-0489-e042.hcd
```

The helper validates the exact size and SHA-256 digest before installation and refuses to overwrite a different existing file.

After rebooting, verify that the patch was loaded:

```bash
journalctl -b -k --no-pager | grep -E 'BCM20702|0489|e042|firmware Patch'
```

A successful boot includes a line similar to:

```text
Bluetooth: hci0: BCM20702A1 'brcm/BCM20702A1-0489-e042.hcd' Patch
```

## OBEX integration

On Debian 13, Bluetooth file-transfer integration required the Evolution data source registry. Install it with:

```bash
sudo apt install evolution-data-server
```

Verify both user services:

```bash
systemctl --user status obex.service evolution-source-registry.service
```

## BlueZ configuration directory mode

The packaged BlueZ unit requests `ConfigurationDirectoryMode=0555`, while a normal administrator-managed `/etc/bluetooth` directory may already be mode `0755`. systemd can warn when the requested mode does not match the existing directory.

The supplied drop-in aligns the unit with the established configuration directory mode:

```text
systemd/bluetooth.service.d/directory-mode.conf
```

Install it with:

```bash
sudo install -D -m 0644 \
  systemd/bluetooth.service.d/directory-mode.conf \
  /etc/systemd/system/bluetooth.service.d/directory-mode.conf
sudo systemctl daemon-reload
sudo systemctl restart bluetooth.service
```

This changes only `/etc/bluetooth`. BlueZ state remains private under `/var/lib/bluetooth` with mode `0700`.

## Privacy

Do not publish `/var/lib/bluetooth`, pairing databases, link keys, controller addresses, or device addresses. None of those are required to reproduce the hardware fix.
