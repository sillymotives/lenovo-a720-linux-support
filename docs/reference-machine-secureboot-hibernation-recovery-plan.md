# Reference machine: Secure Boot, prettyboot, hibernation, and recovery plan

Status date: 2026-07-31

This note records the current state of the Lenovo IdeaCentre A720 reference
machine before an offline storage-layout change and another Secure Boot pass.
It is deliberately text-only and excludes recovery media, signed EFI binaries,
private keys, certificates, filesystem UUIDs, firmware images, NVRAM dumps, and
other machine-local secrets.

## Required final outcome

The target is not a compromise between features. The reference machine is
expected to provide all three of the following:

1. the Darkstar graphical standalone GRUB path ("prettyboot");
2. UEFI Secure Boot with a verifiable signed loader and kernel chain; and
3. reliable suspend-to-disk hibernation.

The work must preserve the stock Debian shim and stock Debian kernel as recovery
routes until the complete custom path has been demonstrated under real cold
boots and repeated resume tests.

## Proven physical state

The following behavior has been demonstrated on the physical machine:

- 16 GiB of matching DDR3 memory is installed and operating at 1600 MT/s;
- Secure Boot disabled exposes kernel hibernation and removes lockdown;
- a 20 GiB swapfile on the root filesystem can hold a hibernation image;
- the kernel received the correct containing-device and resume-offset values;
- `systemd-logind` reported hibernation available;
- one controlled hibernation test powered the machine off and restored the
  original session;
- the boot ID remained unchanged across that test, proving resume rather than a
  normal reboot;
- the Darkstar ignition-ring standalone GRUB image displayed successfully when
  selected with the one-shot UEFI `BootNext` mechanism;
- the normal Debian shim entry remains bootable as the fallback path.

The currently installed 20 GiB swapfile is a successful experiment, not the
intended final storage layout.

## Current storage issue

The machine began with a small dedicated swap partition. During the RAM and
hibernation work an additional swapfile was introduced, then replaced with one
20 GiB hibernation swapfile. This proved the resume path but left the old swap
partition unused and created an unnecessarily complicated final design.

The intended repair is an offline repartition:

- leave the EFI System Partition unchanged;
- shrink only the right-hand end of the ext4 root filesystem;
- remove the old small swap partition;
- create one 20 GiB Linux swap partition in the resulting space;
- remove the swapfile after the new partition is active and tested;
- configure initramfs-tools to resume directly from the new swap partition;
- rebuild all retained initramfs images;
- repeat the controlled hibernation test before enabling Secure Boot.

The ext4 filesystem must be checked and shrunk while unmounted. The filesystem
must be resized before its partition boundary is reduced. The EFI System
Partition must not be formatted, moved, or repurposed.

## Secure Boot and hibernation policy

On the stock Debian kernel, enabling Secure Boot activates kernel lockdown.
Lockdown explicitly blocks hibernation because a mutable image kernel is
restored from disk. Replacing the swapfile with a partition improves the storage
design but does not, by itself, remove this policy conflict.

The upstream and Debian kernel configuration separates three relevant choices:

- `CONFIG_LOCK_DOWN_IN_EFI_SECURE_BOOT` automatically enters integrity lockdown
  when firmware Secure Boot is enabled;
- `CONFIG_HIBERNATION` provides suspend-to-disk support; and
- `CONFIG_MODULE_SIG_FORCE` requires every loadable module to carry a valid
  signature trusted by the running kernel.

This provides a coherent candidate route for the reference machine:

1. build a Debian-derived kernel with hibernation enabled;
2. disable only automatic lockdown on EFI Secure Boot;
3. keep mandatory module-signature enforcement enabled;
4. give the kernel a distinct local version and retain module-version checks;
5. sign the kernel image with the enrolled owner key;
6. sign the A720 DKMS module and every other out-of-tree module with a trusted
   key;
7. retain the stock Debian kernel, which continues to use normal lockdown under
   Secure Boot, as the conservative fallback.

This is a deliberate security-policy choice, not equivalent to stock Debian
lockdown. Secure Boot still authenticates the firmware-to-loader-to-kernel path,
and mandatory module signatures can protect the module-loading boundary, but an
unsigned hibernation image remains mutable offline. That reduced integrity
claim must stay visible in the documentation and acceptance tests.

## Prettyboot source audit

The one-shot boot test proved that the current standalone GRUB payload can show
the Darkstar ignition ring and hand off to Debian. The permanent boot order was
not stable during earlier testing, so future promotion must happen only after
Secure Boot and hibernation are both proven.

A source audit corrected an earlier false alarm: leading `+` characters before
GRUB theme components are required grammar, not accidental diff markers. The
tracked declarations such as `+ label`, `+ boot_menu`, and
`+ circular_progress` match the GNU GRUB theme format. The circular component
uses the special `__timeout__` identifier and the builder generates and embeds
both ignition-ring PNG assets.

The tracked standalone builder also performs the necessary reproducibility and
trust checks:

- generates the ignition assets from source;
- embeds the theme and all required fonts;
- inherits Debian distribution SBAT rows and appends `grub.darkstar`;
- verifies the embedded SBAT bytes;
- signs the final image with a locally supplied owner key;
- verifies the signature against the supplied certificate;
- verifies that the PE certificate table exists within the final file; and
- makes no ESP or EFI-variable changes during a build.

Required prettyboot validation sequence:

1. build from a clean repository checkout;
2. verify the inherited and project SBAT rows;
3. sign the standalone GRUB image with the locally held owner key;
4. verify the PE signature and certificate-table placement;
5. stage the image without overwriting the Debian fallback;
6. test it first with `BootNext` while Secure Boot is enabled;
7. confirm the running system reports the Darkstar entry as `BootCurrent`;
8. perform a cold boot and hibernate-resume cycle through that path;
9. promote it permanently only after all tests pass.

No private key, certificate, signed EFI image, or ESP backup belongs in this
public repository.

## Recovery position

The owner has retained:

- the original Linux installation files from the machine's first Debian setup;
- a current ReaR recovery ISO;
- a separately supplied checksum manifest; and
- a file-level ReaR backup that includes the root filesystem and EFI System
  Partition contents.

Those recovery artifacts remain private and must not be committed. Before the
offline partition edit, verify the recovery ISO checksum, inspect its boot
catalog, confirm the archive stream is readable, confirm the known-good
prettyboot payload is present in the archive, and boot the recovery medium once
without starting a restore.

The Kingston DataTraveler containing ReaR backups is protected media. It must
not be reformatted, repartitioned, used as a bootloader experiment target, or
used as temporary workspace.

## Read-only integrated preflight

`tools/preflight-secureboot-hibernation.sh` performs the machine-side checks
without changing system state. It accepts paths to the recovery ISO, checksum
manifest, and ReaR archive, writes a private local report under `/root`, and
checks:

- disk identity, GPT consistency, and estimated ext4 shrink margin;
- current swap, resume, Secure Boot, and lockdown state;
- EFI entries, prettyboot hash, signature table, MOK signer match, and SBAT;
- current kernel policy, DKMS signer state, and kernel-build prerequisites;
- repository cleanliness and the expected GRUB theme syntax;
- recovery ISO checksum and boot metadata; and
- complete ReaR archive listing plus the archived prettyboot hash.

The script does not mount, unmount, repartition, resize, sign, copy to the ESP,
or alter EFI variables.

## Execution gates

Do not proceed to the next gate until the current one has evidence attached to
the private maintenance log.

### Gate 1A: local read-only preflight

- fetch the preflight script from the draft branch without switching the local
  working tree;
- identify the recovery ISO, checksum manifest, and ReaR archive paths;
- verify the protected backup volume by identity before any read-only mount;
- run the integrated preflight with all three paths;
- obtain zero mandatory failures;
- preserve the generated report under `/root`.

### Gate 1B: physical recovery boot

- boot the recovery medium without starting a restore;
- confirm keyboard, display, internal disk, and protected backup device are
  visible in the rescue environment;
- do not mount the internal root filesystem read-write;
- do not start `rear recover`;
- return to Debian without writing either disk.

### Gate 2: offline storage repair

- boot a separate live environment;
- verify the internal disk identity before making changes;
- run a forced ext4 check while the root filesystem is unmounted;
- shrink the filesystem before changing the partition boundary;
- recreate one 20 GiB swap partition;
- make no change to the EFI System Partition or protected backup media.

### Gate 3: Debian repair and hibernation

- boot through the stock Debian fallback;
- update `fstab` and initramfs resume configuration to the new swap UUID;
- remove the swapfile only after the partition is active;
- rebuild all retained initramfs images;
- verify the kernel resume target;
- complete repeated controlled hibernate-resume tests with Secure Boot disabled.

### Gate 4: custom kernel policy

- build a Debian-derived kernel with automatic EFI lockdown disabled;
- retain hibernation, module versioning, and mandatory module signatures;
- sign the kernel and out-of-tree modules with trusted local keys;
- install it alongside, not over, the stock Debian kernels;
- test boot, module loading, and repeated hibernation while Secure Boot remains
  disabled.

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
- verify the stock Debian path still boots with its normal lockdown policy;
- only then consider changing the permanent boot order.

## Failure policy

A failure at any gate is diagnostic information, not permission to improvise
with the ESP or recovery drive. Restore the last proven state, preserve logs,
and change one variable per test. The original installation material and ReaR
media make a clean rebuild possible, but full restoration is the emergency
path, not the first response to a reversible configuration fault.
