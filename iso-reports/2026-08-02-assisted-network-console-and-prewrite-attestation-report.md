# Lenovo A720 assisted network-console and pre-write attestation report

**Report ID:** A720-PHYSICAL-2026-08-02-01

**Evidence date:** 2026-08-02

**Report issued:** 2026-08-02T18:14:00Z

**Repository:** `sillymotives/lenovo-a720-linux-support`

**Classification:** public, sanitised

**Assurance type:** constrained first-party physical evidence report

**Overall result:** pass for authenticated remote read-only inventory; destructive work remains closed

## Purpose

Record the physical result of booting the assisted Debian Installer generation,
completing the isolated local installer mirror, establishing the generation-pinned
SSH channel, and collecting target-disk evidence before any destructive action.

This report does not authorise partitioning, formatting, LUKS creation, LVM
creation, restoration, EFI-variable modification, or any other target write.

## Evidence handling

The public record deliberately excludes:

- network addresses;
- raw disk serials and stable-path identifiers;
- partition and filesystem UUIDs;
- raw SSH keys and full fingerprint values;
- first- and last-region disk hashes;
- recovery-media contents; and
- any future LUKS or recovery material.

Those values are retained in private, hashed operator evidence where applicable.

## Assisted generation

The physically tested generation was:

```text
kai-assisted-wired-netcfg-v9-20260802T160632Z
```

The active generation used the official Debian Installer kernel and a revised
assisted initrd. Publicly reproducible digests recorded during staging were:

```text
installer kernel SHA-256  e7667ff961fcf0f872e2618a930454a6362ce58995f386431f60a5169c85f41a
revised initrd SHA-256    7306aced35df045f4b4178b95d4c4109692d85410b677c710f788ff5573fdcd6
firmware package SHA-256 925755a9b0891c7dc39bbb73d28ab8f7193d37303b5022e8bc9d458b9b4aaa4e
```

The generation manifest verified during staging. The staging receipt did not
emit a separate digest of the manifest file itself, so that exact public value
remains an evidence-recording gap rather than being reconstructed or guessed.

The runtime policy pinned the wired Realtek interface, allowed 30 seconds for
carrier, allowed 60 seconds for DHCP, and required a reachable SSH endpoint
before the client helper would proceed.

## Firmware and local mirror result

The exact ReaR-proven Realtek firmware payloads were injected and verified by
SHA-256. Runtime lookup and archive placement were proved before activation.

The isolated Debian Installer mirror was expanded from a minimal mirror to the
complete signed amd64 installer package set referenced by the configured Trixie
indexes:

```text
packages mirrored  428
maximum payload     167.3 MiB
new downloads       417
verified reuse      11
```

Every mirrored udeb was checked against metadata chained to Debian's signed
Trixie `InRelease`. The required packages were then fetched through the local
HTTP service and reverified, including:

- `network-console`;
- `openssh-server-udeb`;
- `apt-setup-udeb`; and
- `apt-mirror-setup`.

The A720 subsequently downloaded the required installer components successfully
from the isolated host.

## Authenticated remote-control result

The A720 started Debian Installer `network-console` and accepted public-key-only
SSH authentication for the `installer` account.

The client verified:

- the generation-specific ED25519 client key;
- the A720 ED25519 server key against the fingerprint displayed physically on
  the A720;
- password authentication disabled by policy;
- strict known-host checking; and
- no tunnelling or DNS host-key verification fallback.

The initial lease-scanning helper did not select the endpoint after the installer
configuration changed from DHCP discovery to a stable manual address. A direct,
host-key-pinned client therefore completed the session without weakening the
authentication policy.

Debian Installer placed the remote session inside GNU `screen`. Two failed-safe
client revisions established that the menu required a pseudo-terminal and that
blind numeric menu input was unreliable. The successful client explicitly
switched to the existing shell window, ran read-only commands, received both
completion markers, detached from `screen`, and closed the SSH session cleanly.

## Platform identity

The remote shell positively identified the inspected machine as:

```text
vendor            LENOVO
product           IdeaCentre A720
machine type      2564
system board      ChiefRiver
firmware version  ERKT15AUS
firmware date     2012-08-23
installer kernel  6.12.94+deb13-amd64
```

The rescue environment was a RAM-backed Debian Installer root filesystem. EFI
runtime services were present and the firmware platform size was 64 bits.

## Target-disk discovery

Exactly one internal ATA SSD was discovered. Its unique serial and stable
`/dev/disk/by-id` path are retained privately.

The public, non-unique geometry and media characteristics were:

```text
model class            Fanxiang S101 256 GB
exact bytes            256060514304
logical sector bytes   512
physical sector bytes  512
rotational             no
removable              no
session device node    /dev/sda
```

The session device node is recorded only as runtime context. It is not accepted
as durable target identity.

## Existing storage state

Read-only partition and filesystem inspection found a GPT with the following
pre-existing layout:

| Partition | Approximate size | Existing type |
|---|---:|---|
| 1 | 976 MiB | EFI System Partition, FAT |
| 2 | 229.6 GiB | Linux filesystem, ext4 |
| 3 | 8 GiB | Linux swap |

The target disk and all target partitions were unmounted. No active LVM physical
volume, volume group, logical volume, or md RAID device was present.

SHA-256 values for the first and last 4 MiB of the target were captured privately
as change-detection anchors. They are intentionally omitted from this public
report because they fingerprint target contents.

## Firmware-state evidence limitation

The remote evidence proved that EFI runtime services were present and that the
firmware was operating in 64-bit mode. Earlier physical evidence had already
proved acceptance of Debian-signed shim and GRUB while Secure Boot was enabled.

The first pre-write helper attempted to read individual EFI variables with a
BusyBox-compatible shell function. In the raw remote transcript, the helper
returned `absent` for `SecureBoot`, `SetupMode`, `AuditMode`, `DeployedMode`, and
`MokSBStateRT`. That result is not accepted as proof that the variables are
actually absent because the lookup implementation itself was not independently
validated in the Debian Installer environment.

Accordingly:

- EFI runtime presence is proved;
- the earlier signed-boot acceptance evidence remains valid;
- this specific variable-reader result is inconclusive; and
- Secure Boot variable-state evidence must be recollected with a corrected,
  directly enumerated efivar reader before the destructive gate can open.

This limitation is recorded rather than silently converting an ambiguous parser
result into a pass.

## Write-safety result

The successful inventory and attestation sequences used read-only discovery
commands. The target disk was not mounted, partitioned, formatted, opened through
LUKS, added to LVM, or selected as a rescue root filesystem.

No A720 storage, firmware, or NVRAM write was authorised or observed during this
evidence sequence.

The protected Kingston recovery device and SanDisk installation device remained
unmounted and kernel read-only on the provisioning host during staging. Their
final protection still requires physical detachment before any destructive target
operation.

## Control conclusions

### Authenticated remote administration

**Result:** physical pass

Generation-specific public-key authentication, pinned server identity, and a
working remote root shell inside Debian Installer were physically demonstrated.
The loss of this channel remains a stop condition for delicate work.

### Target identity and geometry

**Result:** pass for read-only discovery

A stable private identity, exact byte size, sector geometry, media type, current
GPT, filesystem signatures, and edge-region hashes were collected. The runtime
node alone remains insufficient identity.

### Target immutability

**Result:** no-write evidence pass for this inspection sequence

The target was writable at the kernel block-device flag level, as expected for an
unmodified internal SSD, but no target-backed mount, holder, LVM object, RAID
object, or destructive command was used. This does not close the separate signed
installer zero-write preflight finding in draft pull request 6.

### Signed destructive environment

**Result:** not yet tested

The official signed PXE and assisted read-only paths are proven. The final signed
installer UKI, authenticated command line, production signing ceremony, and
runtime-contract evidence are still pending.

## Decision

The following non-destructive work may continue:

- correct and retest EFI variable-state collection;
- capture the active generation-manifest file digest;
- build and inspect the signed installer UKI;
- verify UKI sections, signatures, SBAT, embedded command line, and complete
  initramfs; and
- prepare an independently recalculated partition map without applying it.

The following remain prohibited:

- deleting the current GPT or filesystem signatures;
- creating or modifying partitions;
- formatting any target partition;
- creating LUKS2 or LVM objects;
- restoring data;
- changing EFI variables for installation; and
- beginning destructive work while either protected USB device is attached.

## Required next evidence

Before the destructive gate can be considered, collect and record:

1. the exact SHA-256 digest of the active generation's manifest file;
2. corrected Secure Boot and setup-mode variable evidence;
3. signed UKI build provenance and signature verification;
4. the physically booted UKI runtime contract and zero-write preflight;
5. physical detachment of both protected removable devices;
6. an independently recalculated sector map for the approved target layout; and
7. an explicit typed owner authorisation tied to the exact target identity and
   evidence bundle.
