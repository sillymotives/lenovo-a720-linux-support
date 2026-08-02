# Reference machine: final partition-layout amendment

Status date: 2026-08-02

This amendment fixes two details of the planned clean network-provisioned rebuild
for the Lenovo IdeaCentre A720 reference machine:

1. the EFI System Partition will be 2 GiB; and
2. the final 5 GiB of the disk will be a dedicated FAT32 partition reserved as
   Kai's permanent space on the machine.

This amendment supplements
`reference-machine-network-boot-amendment.md`. The later
`reference-machine-authenticated-boot-storage-amendment.md` fixes the LUKS2,
LVM, UKI, lockdown, key-recovery, and mount-policy implementation details. None
of these documents authorizes disk changes before the read-only network-boot and
recovery gates pass.

## Required disk order

The GPT layout must preserve this order from the beginning to the end of the
internal disk:

```text
internal disk
  -> 2 GiB EFI System Partition, FAT32
  -> LUKS2 encrypted system partition
       -> LVM volume group `darkstar`
            -> ext4 logical volume `root`
            -> dedicated 20 GiB logical volume `swap`
            -> 5% of volume-group extents left unallocated
  -> 5 GiB FAT32 partition at the physical end of the GPT
```

All partition boundaries must use normal alignment. The 5 GiB reservation is
taken from the end of the disk before sizing the LUKS2 system partition.

There is no separate plaintext `/boot`, `/home`, `/var`, or `/tmp` partition.
The `/boot` directory remains inside encrypted root, while signed EFI boot
artifacts reside on the ESP.

## EFI System Partition

The EFI System Partition must:

- be 2 GiB in size;
- use the GPT EFI System Partition type;
- be formatted FAT32;
- contain the stock Debian signed fallback alongside the staged Darkstar path;
- retain the current and previous-known-good signed Darkstar UKIs;
- retain enough working room for signed kernels, UKIs, recovery copies, and
  future boot-chain experiments; and
- never be used as general data storage.

The larger size is deliberate. It is not permission to overwrite known-good
fallback loaders or to store private signing keys, LUKS recovery material, or
other secrets on the ESP.

Linux-side modification of the ESP must be restricted to root under the reviewed
maintenance path. Every promoted boot artifact must be verified after copying
and followed by an updated private ESP archive and hash manifest.

## Encrypted system partition

The LUKS2 partition contains one LVM volume group named `darkstar`.

The volume group must contain:

- one ext4 root LV named `root`;
- one dedicated 20 GiB swap LV named `swap`; and
- exactly 5% of the VG extents left unallocated after initial installation.

The unallocated reserve is intentional recovery and maintenance headroom. It
must not be silently consumed during installation, package setup, restoration,
or routine filesystem growth.

## Kai's permanent partition

The final 5 GiB partition must:

- occupy the physical end of the GPT;
- use a normal Microsoft basic-data GPT type suitable for FAT32;
- be formatted FAT32;
- have the GPT partition name `Kai's super secret special place`;
- use the FAT volume label `KAI_SECRET`;
- remain outside the encrypted system partition; and
- have no initial `/etc/fstab` entry or desktop automount rule.

FAT volume labels are limited to eleven characters, so the complete phrase
belongs in the GPT partition name while the filesystem label uses the compact
`KAI_SECRET` form.

Despite its name, the partition is not cryptographically secret. FAT32 provides
no encryption, ownership model, or meaningful access control. It must not hold
credentials, private keys, LUKS headers, recovery archives, personal records, or
other sensitive material unless those files are independently encrypted first.

If a later reviewed configuration mounts it, the baseline mount options are:

```text
nodev,nosuid,noexec,umask=077
```

## Permanence and preservation rule

The partition is part of the intended final machine layout, not temporary
installer scratch space.

Future operating-system reinstalls, recovery work, and partition maintenance
must preserve it unless the machine owner explicitly revokes that reservation.
Installers and recovery scripts must not absorb it into the LUKS2 partition,
format it as part of an automatic layout, or reuse it for swap, `/boot`, rescue
images, or network-boot staging.

## Installation gate additions

Before destructive installation begins:

- calculate the usable disk space after reserving the 2 GiB ESP and final 5 GiB
  FAT32 partition;
- record the exact logical and physical sector sizes;
- record the proposed aligned partition start and end sectors in the private
  maintenance log;
- independently verify that the final 5 GiB partition is physically last,
  regardless of its numeric partition index;
- verify that the 20 GiB swap LV and 5% unallocated VG reserve fit inside the
  proposed LUKS2 partition; and
- physically detach all removable storage before the first write.

After partitioning and before installing machine-specific customization:

- verify the ESP is 2 GiB and FAT32;
- verify the LUKS2 partition occupies only the intended middle region;
- verify VG `darkstar`, LV `root`, LV `swap`, and the 5% unallocated extent
  reserve;
- verify the Kai partition is 5 GiB, FAT32, and physically last;
- verify its GPT name is exactly `Kai's super secret special place`;
- verify its FAT label is exactly `KAI_SECRET`;
- verify neither FAT partition overlaps the LUKS2 partition;
- preserve binary and textual GPT backups privately; and
- preserve a textual partition, LUKS, and LVM report in the private maintenance
  log.

## Acceptance addition

The rebuild is not complete until final certification confirms that:

- the 2 GiB ESP remains healthy and contains the stock, current custom, and
  previous-known-good signed boot paths;
- the LUKS2 partition contains the intended `darkstar` LVM layout;
- the 20 GiB swap LV is the only hibernation swap target;
- 5% of the VG remains unallocated;
- the 5 GiB Kai partition remains present, physically last, correctly named,
  correctly labelled, unmounted by default, and untouched by encrypted-system
  maintenance; and
- the GPT backup and exact sector report are test-readable.
