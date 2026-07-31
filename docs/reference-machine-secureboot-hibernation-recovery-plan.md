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
2. UEFI Secure Boot with a verifiable signed loader chain; and
3. reliable suspend-to-disk hibernation.

The work must preserve the stock Debian shim path as a recovery route until the
complete chain has been demonstrated under real cold boots and resume tests.

## Proven state

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

## Secure Boot and hibernation boundary

On the stock Debian kernel, enabling Secure Boot activates kernel lockdown.
That policy blocks hibernation even when the bootloader, kernel, and swap layout
are otherwise correct. Replacing the swapfile with a partition improves the
storage design but does not, by itself, remove this policy conflict.

Therefore the final implementation needs an explicit, reviewed kernel policy
rather than pretending the conflict does not exist. Candidate work includes:

- determine whether an appropriately configured custom Debian kernel can keep
  Secure Boot verification while permitting hibernation on this machine;
- document exactly which lockdown guarantees are relaxed and why;
- sign the resulting kernel and every out-of-tree kernel module with keys that
  are trusted by the enrolled owner chain;
- keep the stock Debian kernel and loader available as a fallback;
- test cold boot, module loading, hibernation image creation, and resume under
  Secure Boot rather than inferring success from static signatures alone.

A custom kernel that permits hibernation under Secure Boot is a deliberate
security-policy choice. It must be described honestly: resume restores mutable
kernel memory from disk, so allowing it changes the integrity model provided by
lockdown.

## Prettyboot status and repair items

The one-shot boot test proved that the current standalone GRUB payload can show
the Darkstar ignition ring and hand off to Debian. The permanent boot order was
not stable during earlier testing, so future promotion must happen only after
Secure Boot and hibernation are both proven.

Known repository-side issue:

- the tracked Darkstar GRUB theme currently contains literal leading `+`
  characters before two graphical component declarations. Those markers must
  be removed before any clean rebuild is considered authoritative.

Required prettyboot validation sequence:

1. rebuild from a clean repository checkout after fixing the theme source;
2. inherit and verify the distribution SBAT rows;
3. sign the standalone GRUB image with the locally held owner key;
4. verify the PE signature and certificate-table placement;
5. stage the image without overwriting the Debian fallback;
6. test it first with `BootNext` while Secure Boot is enabled;
7. confirm the running system reports the Darkstar entry as `BootCurrent`;
8. perform a cold boot and a hibernate-resume cycle through that path;
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
offline partition edit, verify the recovery ISO checksum, confirm the archive
stream is readable, and perform at least one boot test of the recovery medium.

The Kingston DataTraveler containing ReaR backups is protected media. It must
not be reformatted, repartitioned, used as a bootloader experiment target, or
used as temporary workspace.

## Execution gates

Do not proceed to the next gate until the current one has evidence attached to
the private maintenance log.

### Gate 1: recovery readiness

- verify the supplied checksum manifest against the recovery ISO;
- boot the recovery medium without starting a restore;
- confirm the backup archive can be listed and tested;
- capture the current partition table and EFI entry list privately.

### Gate 2: offline storage repair

- boot a separate live environment;
- verify the internal disk identity before making changes;
- shrink the unmounted root filesystem and root partition;
- recreate one 20 GiB swap partition;
- make no change to the EFI System Partition or protected backup media.

### Gate 3: Debian repair and hibernation

- boot through the stock Debian fallback;
- update `fstab` and initramfs resume configuration to the new swap UUID;
- remove the swapfile only after the partition is active;
- rebuild all retained initramfs images;
- verify the kernel resume target;
- complete one controlled hibernate-resume test with Secure Boot disabled.

### Gate 4: Secure Boot engineering

- fix the tracked theme syntax;
- select and document the kernel-lockdown policy;
- build and sign the complete trusted chain locally;
- verify all signatures and SBAT data;
- keep the stock Debian path untouched.

### Gate 5: integrated certification

With Secure Boot enabled and Darkstar selected through `BootNext`:

- confirm the firmware accepted the signed chain;
- confirm the intended kernel and signed modules loaded;
- confirm prettyboot appeared;
- confirm hibernation is offered;
- hibernate and resume successfully;
- cold boot again;
- only then consider changing the permanent boot order.

## Failure policy

A failure at any gate is diagnostic information, not permission to improvise
with the ESP or recovery drive. Restore the last proven state, preserve logs,
and change one variable per test. The original installation material and ReaR
media make a clean rebuild possible, but full restoration is the emergency
path, not the first response to a reversible configuration fault.
