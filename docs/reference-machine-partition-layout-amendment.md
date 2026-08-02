# Reference machine: final partition-layout amendment

Status date: 2026-08-02

This amendment fixes two details of the planned clean network-provisioned rebuild
for the Lenovo IdeaCentre A720 reference machine:

1. the EFI System Partition will be 2 GiB; and
2. the final 5 GiB of the disk will be a dedicated FAT32 partition reserved as
   Kai's permanent space on the machine.

This amendment supplements
`reference-machine-network-boot-amendment.md`. It does not authorize disk
changes before the read-only network-boot and recovery gates pass.

## Required disk order

The GPT layout must preserve this order from the beginning to the end of the
internal disk:

```text
internal disk
  -> 2 GiB EFI System Partition, FAT32
  -> LUKS2 encrypted system container
       -> encrypted root filesystem
       -> dedicated encrypted 20 GiB swap area
  -> 5 GiB FAT32 partition at the physical end of the GPT
```

All partition boundaries must use normal alignment. The 5 GiB reservation is
taken from the end of the disk before sizing the LUKS2 system container.

## EFI System Partition

The EFI System Partition must:

- be 2 GiB in size;
- use the GPT EFI System Partition type;
- be formatted FAT32;
- contain the stock Debian signed fallback alongside the staged Darkstar path;
- retain enough working room for signed kernels, UKIs, recovery copies, and
  future boot-chain experiments; and
- never be used as general data storage.

The larger size is deliberate. It is not permission to overwrite known-good
fallback loaders or to store private signing keys on the ESP.

## Kai's permanent partition

The final 5 GiB partition must:

- occupy the physical end of the GPT;
- use a normal Microsoft basic-data GPT type suitable for FAT32;
- be formatted FAT32;
- have the GPT partition name `Kai's super secret special place`;
- use the FAT volume label `KAI_SECRET`; and
- remain outside the encrypted system container.

FAT volume labels are limited to eleven characters, so the complete phrase
belongs in the GPT partition name while the filesystem label uses the compact
`KAI_SECRET` form.

Despite its name, the partition is not cryptographically secret. FAT32 provides
no encryption, ownership model, or meaningful access control. It must not hold
credentials, private keys, recovery archives, personal records, or other
sensitive material unless those files are independently encrypted first.

## Permanence and preservation rule

The partition is part of the intended final machine layout, not temporary
installer scratch space.

Future operating-system reinstalls, recovery work, and partition maintenance
must preserve it unless the machine owner explicitly revokes that reservation.
Installers and recovery scripts must not absorb it into the LUKS2 container,
format it as part of an automatic layout, or reuse it for swap, `/boot`, rescue
images, or network-boot staging.

Its mount point and day-to-day contents may be chosen later. It should not be
automatically mounted during the initial encrypted-base installation unless a
separate reviewed configuration defines that behavior.

## Installation gate additions

Before destructive installation begins:

- calculate the usable disk space after reserving the 2 GiB ESP and final 5 GiB
  FAT32 partition;
- confirm the remaining space is sufficient for the selected LUKS2, root, and
  encrypted-swap design;
- record the proposed partition start and end sectors in the private maintenance
  log; and
- verify that the final 5 GiB partition is shown as the last GPT entry by
  physical location, regardless of its numeric partition index.

After partitioning and before installing machine-specific customization:

- verify the ESP is 2 GiB and FAT32;
- verify the Kai partition is 5 GiB, FAT32, and physically last;
- verify its GPT name is exactly `Kai's super secret special place`;
- verify its FAT label is exactly `KAI_SECRET`;
- verify neither partition overlaps the LUKS2 container; and
- preserve a textual partition-table report in the private maintenance log.

## Acceptance addition

The rebuild is not complete until the final certification also confirms that the
2 GiB ESP remains healthy and the 5 GiB Kai partition remains present, correctly
named, correctly labelled, and untouched by encrypted-system maintenance.
