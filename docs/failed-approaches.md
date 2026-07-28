# Why the earlier approaches failed

## Standard input and HID probing

The bezel is not exposed as an ordinary keyboard, consumer-control HID device, touchscreen zone, or standard ACPI hotkey device. Consequently, `xev`, `evtest`, `acpi_listen`, and direct CoolTouch `hidraw` reads did not reveal the controls.

## Display scaler and DDC/CI

The A720's internal display and several I2C devices were visible, but they did not carry the bezel events. A blank `i2cdump` does not prove that a device is locked or awaiting a secret handshake.

## Fixed event-payload mappings

Initial events looked like:

```text
16 00 01 2b
16 00 01 3f
16 00 01 53
...
```

It was tempting to map byte 3 directly to buttons. That failed because the same control produced different values and different controls sometimes produced the same value.

Static analysis showed that Lenovo's utility ignores this byte for the relevant volume flow. The useful absolute volume appears only after the second-stage `0xa7` query, in response byte 5.

## Treating 0x16 and 0x17 as directions

They are protocol stages, not Up and Down:

- `0x16`: synchronize current OS volume
- `0x17`: requested volume is available

## Querying without synchronization

A diagnostic that implemented only the `0x17` query received repeated `0x16` events. Once Linux answered `0x16` with the exact `0xa8` synchronization packet, the controller emitted `0x17` and returned valid values.

## Audio-backend mismatch

The first user-space bridge used `wpctl`, but the test system ran native PulseAudio. Installing the binary did not turn the session into PipeWire. The bridge now detects a working backend and uses `pactl` or `wpctl` accordingly.
