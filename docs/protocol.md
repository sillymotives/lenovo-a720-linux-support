# Reverse-engineered WMI protocol

## Firmware objects

The A720 firmware advertises:

```text
ABBC0F20-8EA1-11D1-00A0-C90629100000  event channel
ABBC0F40-8EA1-11D1-00A0-C90629100000  I/O data block
```

Initialization uses command `01 10 02`, which reaches the ACPI `WINI()` path and enables event delivery by incrementing the firmware subscriber counter.

## Volume exchange

### Synchronization

On WMI event `0x16`, the original Windows utility reads the operating-system volume and sends:

```text
01 10 05 03 03 a8 VV
```

`VV` is an absolute percentage from 0 to 100.

### Requested volume

On WMI event `0x17`, the utility sends:

```text
01 10 04 02 03 a7
```

It then queries the `ABBC0F40` block. Byte 5 of the 64-byte response contains the requested absolute volume.

Observed example from a synchronized 50 percent baseline:

```text
Three Volume Up touches   -> response[5] = 56
Three Volume Down touches -> response[5] = 42
```

## Brightness

Static analysis of the Windows utility associates events `0x13` and `0x14` with brightness directions. The Linux implementation has not yet reproduced the brightness control path.
