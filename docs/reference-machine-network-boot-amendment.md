# Reference machine: network-boot recovery amendment

Status date: 2026-08-02

This amendment supersedes the removable-media recovery and offline-live-boot
parts of `reference-machine-secureboot-hibernation-recovery-plan.md`.
The final machine goals remain unchanged:

1. the Darkstar graphical standalone GRUB path ("prettyboot");
2. UEFI Secure Boot with a verifiable signed loader and kernel chain; and
3. reliable suspend-to-disk hibernation.

The storage repair and recovery environment will now be delivered over the
local network instead of from a bootable USB device. The Kingston DataTraveler
remains protected backup media and is not part of the boot chain.

## Why the plan changed

A network-delivered rescue environment is easier to reproduce, inspect, and
replace without rewriting removable media. It also separates three roles that
must not be confused:

- the A720 is the repair target;
- a separate trusted machine provides boot and recovery assets; and
- the Kingston device remains an offline or selectively attached backup source.

This amendment does not assume that the A720 firmware network path is already
proven. Firmware PXE or UEFI HTTP/iPXE compatibility is an acceptance gate, not
a fact inferred from the presence of an Ethernet controller.

## Trust boundary

The network-boot server must be a separate trusted machine on the local wired
network. Its private addresses, interface names, DHCP configuration, MAC
addresses, credentials, and machine-local paths do not belong in the public
repository.

The server may provide the first-stage network loader by the mechanism supported
by the A720 firmware, then deliver the selected kernel, initramfs, and optional
root filesystem over the local network. The repository may document the shape
of that chain, but must not commit private recovery archives, signed EFI
binaries, private keys, certificates containing private deployment details, or
machine identifiers.

Every boot artifact must have a recorded SHA-256 digest. The manifest must be
stored separately from the generated images and checked both on the server and
from the booted rescue environment. A detached signature may be added later,
but a signature does not replace checking that the correct machine, disk, boot
entry, and recovery generation were selected.

## Required network-boot behavior

The default network entry must be non-destructive. Merely selecting network boot
must never:

- start `rear recover` or another restore workflow;
- mount the internal root filesystem read-write;
- activate, reformat, or repartition the Kingston device;
- alter the EFI System Partition;
- change EFI variables or the permanent boot order;
- run filesystem repair or partitioning tools automatically; or
- accept an unattended destructive timeout choice.

The first menu entry must be a read-only inspection environment. Any later
repair entry must require explicit operator selection and must stop at a shell or
an equivalent confirmation boundary before disk-changing commands are issued.

## Network-boot server preparation

Before the A720 attempts a network boot:

- place the selected rescue kernel, initramfs, and any root image in a dedicated
  versioned directory on the trusted server;
- create a SHA-256 manifest covering every delivered boot artifact;
- record the source and build date of the rescue environment;
- keep an immediately previous known-good generation available;
- configure a machine-specific or manually selected boot entry without
  publishing the A720 MAC address in this repository;
- ensure the default menu path is the read-only inspection environment;
- disable automatic restore, automatic partitioning, and writable automounts;
- verify the server is not exporting private backup material anonymously; and
- test the same boot entry in an expendable virtual machine where practical.

DHCP, proxy-DHCP, TFTP, HTTP, NFS, and iPXE are implementation choices rather
than requirements of this public plan. Use only the minimum services needed for
the firmware and selected rescue environment. Prefer transferring larger
artifacts over HTTP or another checksummed transport after the smallest viable
first stage has loaded.

## Recovery data position

The owner retains:

- the original Linux installation files from the machine's first Debian setup;
- a current ReaR recovery image and checksum information; and
- a file-level ReaR backup that includes the root filesystem and EFI System
  Partition contents.

Those artifacts remain private. They may be copied to or exposed through the
trusted recovery server only when access is restricted to the maintenance
network and the exact archive digest has been verified. The network-boot menu
must not contain credentials or embed a writable recovery share.

The Kingston DataTraveler containing ReaR backups remains protected media. It
must not be reformatted, repartitioned, used as a bootloader target, used as
network-boot workspace, or assumed to be `/dev/sdb`. Device identity must be
proven from stable properties before it is mounted, and mounting is not part of
the initial network-boot smoke test.

## Effect on the current preflight tool

`tools/preflight-secureboot-hibernation.sh` was written for local ISO and archive
paths plus a removable-media recovery boot. It is retained in the draft for
review history, but it is not the authoritative Gate 1A tool under this amended
plan.

Before use, it must be refactored so that:

- network boot artifacts and their manifest can be checked from a staged local
  copy or a read-only network source;
- the selected server generation is recorded in the private report;
- `/dev/sdb` is never treated as proof of Kingston identity;
- protected-device absence is acceptable during the first smoke test;
- the script distinguishes installed-system preflight from rescue-environment
  preflight; and
- no network share is mounted read-write by the script.

Until that refactor is reviewed and CI passes, the current script is diagnostic
material only and must not be used to authorize repartitioning.

## Revised execution gates

Do not proceed to the next gate until the current gate has evidence attached to
the private maintenance log.

### Gate 0: server-side artifact gate

- identify the exact rescue-environment generation;
- verify all boot-artifact SHA-256 values against the separate manifest;
- inspect the network menu and prove the default entry is non-destructive;
- confirm no private key or credential is embedded in a served file;
- confirm the previous known-good generation remains available; and
- capture the server configuration needed to reconstruct the service privately.

### Gate 1A: installed-system read-only preflight

- verify the internal disk, EFI System Partition, root filesystem, current swap,
  resume configuration, prettyboot payload, Secure Boot state, and lockdown
  state from the installed Debian system;
- record the intended network-boot generation and its manifest digest;
- confirm the wired interface is available without changing the permanent boot
  order;
- do not require the Kingston device to be attached; and
- obtain zero mandatory failures from the revised preflight tool.

### Gate 1B: network-boot smoke test

- select network boot through the firmware's one-shot mechanism or temporary
  boot menu rather than changing the permanent order;
- boot the read-only inspection entry;
- confirm keyboard, display, wired networking, and rescue shell operation;
- verify the delivered kernel and initramfs hashes or generation identity;
- identify the internal disk without mounting its filesystems read-write;
- confirm no restore, repartition, filesystem repair, or writable automount ran;
- leave the Kingston device detached unless a later check specifically requires
  it; and
- return to Debian without writing the internal disk or EFI variables.

### Gate 1C: recovery-path rehearsal

- network boot the same pinned rescue generation;
- confirm the private recovery archive is reachable only through the intended
  restricted path;
- verify the archive digest and complete archive readability;
- confirm the expected root and EFI System Partition members are present;
- do not start a restore;
- do not mount the internal root filesystem read-write; and
- return to Debian without changing either the target disk or backup source.

### Gate 2: network-booted offline storage repair

- boot the pinned repair generation rather than an unversioned latest image;
- verify the internal disk by stable identity before issuing any changing
  command;
- keep the EFI System Partition and protected backup media untouched;
- run a forced ext4 check while the root filesystem is unmounted;
- calculate the authoritative minimum ext4 size after the successful check;
- choose and record a target size with a deliberate safety margin;
- shrink the filesystem before reducing the partition boundary;
- remove the obsolete small swap partition and create one 20 GiB Linux swap
  partition in the intended free space; and
- stop and preserve logs on any discrepancy rather than improvising.

### Gate 3: Debian repair and hibernation

- boot through the stock Debian fallback;
- update `fstab` and initramfs resume configuration to the new swap UUID;
- activate and verify the new swap partition;
- remove the swapfile only after the partition is active and tested;
- rebuild all retained initramfs images;
- verify the running kernel's resume target; and
- complete repeated controlled hibernate-resume tests with Secure Boot disabled.

### Gate 4: custom kernel policy

- build a Debian-derived kernel with automatic EFI lockdown disabled;
- retain hibernation, module versioning, and mandatory module signatures;
- sign the kernel and out-of-tree modules with trusted local keys;
- install it alongside, not over, the stock Debian kernels; and
- test boot, required module loading, and repeated hibernation while Secure Boot
  remains disabled.

### Gate 5: integrated Secure Boot certification

With Secure Boot enabled and Darkstar selected through `BootNext`:

- confirm the firmware accepted the signed loader and kernel chain;
- confirm the intended custom kernel loaded;
- confirm lockdown is deliberately `none` under that kernel;
- confirm unsigned modules are rejected and required signed modules load;
- confirm prettyboot appeared;
- confirm hibernation is offered;
- hibernate and resume successfully more than once;
- cold boot again;
- verify the stock Debian path still boots with its normal lockdown policy; and
- only then consider changing the permanent boot order.

Network boot remains a recovery and maintenance path. It does not become the
normal permanent boot path merely because the repair succeeds.

## Failure policy

A failure at any gate is diagnostic information, not permission to weaken the
boot server, expose the recovery archive, improvise with the ESP, or attach the
Kingston device blindly. Restore the last proven server generation, preserve
logs, and change one variable per test.

If firmware network boot is unreliable, retain the network artifacts and return
to planning. Do not compensate by converting the protected Kingston backup
device into experimental boot media.
