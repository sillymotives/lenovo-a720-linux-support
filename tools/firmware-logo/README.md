# Firmware-logo tooling

These tools support the documented A720 vendor-splash workflow.

They are intentionally limited to:

- converting artwork to the tested AMI BMP format;
- reading the host BIOS region;
- replacing both known logo resources in an offline copy;
- recording output sizes, replacement logs, and hashes for independent review.

They do not independently validate firmware-volume structure and do not
automatically write firmware.

See [`../../docs/firmware-logo.md`](../../docs/firmware-logo.md) before using them.
