# Reference machine: authenticated boot and storage-hardening amendment

Status date: 2026-08-02

This amendment fixes the remaining implementation choices for the clean,
network-provisioned Lenovo IdeaCentre A720 rebuild. It supplements and, where
there is a conflict, supersedes the implementation details in:

- `reference-machine-secureboot-hibernation-recovery-plan.md`;
- `reference-machine-network-boot-amendment.md`; and
- `reference-machine-partition-layout-amendment.md`.

The physical GPT order and fixed partition sizes remain unchanged. The purpose of
this amendment is to authenticate early userspace and the kernel command line,
retain kernel lockdown while making a narrow hibernation exception, fix the
inside-LUKS layout, and strengthen key, recovery, and post-installation policy.

Nothing in this document authorizes a destructive command before the read-only
inventory, recovery, disk-identity, and exact-sector-layout gates have passed.

## Final physical GPT order

The internal disk must preserve this order from the beginning to the end of the
device:

```text
internal disk
  -> 2 GiB EFI System Partition, FAT32
  -> LUKS2 encrypted system partition
       -> LVM volume group `darkstar`
            -> ext4 logical volume `root`
            -> 20 GiB logical volume `swap`
            -> 5% of volume-group extents left unallocated
  -> 5 GiB FAT32 partition at the physical end of the GPT
       GPT name: Kai's super secret special place
       FAT label: KAI_SECRET
```

The root logical volume consumes the remaining allocated volume-group space after
the fixed 20 GiB swap LV and the 5% unallocated reserve are accounted for.

There will be no separate `/home`, `/var`, `/tmp`, or plaintext `/boot`
partition. A single ext4 root keeps recovery and capacity management simple.
The `/boot` directory remains inside encrypted root. Executable boot artifacts
that firmware must read live on the EFI System Partition as signed EFI images.

## Authenticated boot-artifact rule

The destructive installer path and the final custom Darkstar boot path must use
owner-approved, signed Unified Kernel Images or an equivalently authenticated
single EFI artifact.

Each UKI must bind at least:

- the intended kernel;
- the complete initramfs;
- CPU microcode when included;
- the immutable kernel command line;
- operating-system release metadata; and
- the project's SBAT generation data.

The single PE/COFF signature must authenticate those embedded resources together.
An external unsigned initramfs, mutable external command line, or unsigned addon
must not be able to alter the destructive installer or final custom boot path.

The currently proven separate-kernel-and-initrd PXE generations remain valid for
read-only inspection. They do not authorize partitioning. Before the destructive
gate, a signed installer UKI must be built, signature-checked, hash-pinned,
served as an immutable generation, and physically boot-tested under Secure Boot.

## EFI System Partition contents

The 2 GiB ESP must retain independent recovery choices and enough free space for
updates. Its intended contents include:

1. the stock Debian signed shim and GRUB fallback;
2. the signed Darkstar Prettyboot loader;
3. the current signed Darkstar UKI;
4. the immediately previous known-good signed Darkstar UKI; and
5. a stock-Debian recovery UKI or equivalent signed stock fallback.

Promotion of a new custom artifact must never overwrite the last known-good
custom artifact or the stock Debian fallback in the same operation.

The ESP is not general storage. It must be writable only by root under the
reviewed maintenance path, and every promoted loader or UKI must trigger a new
ESP archive and hash manifest. Private signing keys must never be stored on the
ESP, on `KAI_SECRET`, or in the public repository.

## Secure Boot, lockdown, and hibernation policy

The older candidate of disabling automatic EFI lockdown is rejected for the
final custom path. Secure Boot must continue to enter integrity lockdown.

The final custom kernel must be Debian-derived, owner-signed, and carry a small,
reviewable patch that permits hibernation without disabling the rest of integrity
lockdown. The exception must:

- leave Secure Boot authentication intact;
- leave integrity lockdown active;
- retain mandatory signed-module enforcement;
- retain module-version checks;
- require an explicit project-specific opt-in parameter embedded in the signed
  UKI command line;
- resume only after trusted early userspace has unlocked the intended LUKS2
  container and activated the dedicated swap LV; and
- install alongside, never over, the unmodified stock Debian fallback kernel.

The patch, exact kernel source, Debian configuration delta, resulting binary
hash, signing certificate fingerprint, and build procedure must be preserved.
The patch must not be broadened to disable unrelated lockdown checks.

Encrypted swap protects confidentiality of the hibernation image. Ordinary LUKS
sector encryption does not by itself prove freshness or cryptographic integrity
of every resumed block. Hibernation under this custom path therefore remains an
explicit, documented threat-model choice rather than a claim equivalent to the
stock Debian lockdown policy.

The stock Debian fallback must retain its normal Secure Boot and lockdown
behavior even if that path refuses hibernation.

## LUKS2 key hierarchy

The initial encrypted-base build must use a manually entered LUKS2 passphrase.
Before the disk is considered recoverable, the volume must also have a separately
generated, high-entropy recovery key.

The minimum key hierarchy is:

1. one strong operational passphrase;
2. one generated recovery key stored offline;
3. at least one protected offline LUKS header backup; and
4. optional FIDO2 enrollment only after the manual and recovery-key paths have
   been cold-boot tested.

TPM-assisted automatic unlocking is not part of the initial build. It may be
considered later as a separate reviewed project, and only while a tested
passphrase and recovery key remain enrolled.

Keyslot changes require a refreshed LUKS metadata report and a reviewed decision
about whether the offline header backup also needs replacement. A header backup
is sensitive recovery material: it contains the volume key encrypted by the
keyslots present at backup time and must be protected accordingly.

No passphrase, recovery key, volume key, LUKS header backup, token secret, private
signing key, or machine-specific identifier belongs in Git.

## Recovery evidence package

Immediately after final partitioning, LUKS enrollment, and boot-artifact
promotion, preserve a private recovery evidence package containing at least:

- a binary GPT backup;
- a textual partition table with exact start and end sectors;
- the internal disk's private stable fingerprint and byte geometry;
- a protected LUKS header backup;
- a sanitised `cryptsetup luksDump` report;
- a complete ESP archive and hash manifest;
- signer and enrolled-certificate fingerprints;
- current, previous, and stock-fallback UKI hashes;
- the exact kernel source revision, configuration, and hibernation patch;
- installed cryptsetup, systemd, shim, GRUB, and kernel package versions; and
- concise cold-boot recovery instructions.

The GPT and LUKS backups must be test-readable. Restoration procedures should be
rehearsed against disposable loop-backed images or another non-live target before
they are trusted for the A720.

The historical ReaR set remains a pre-rebuild parachute. After the new encrypted
architecture passes complete certification, create a new recovery set that
understands the final GPT, LUKS2, LVM, ESP, UKI, and key-recovery design, then
perform a non-destructive boot and restore rehearsal.

## FAT filesystem policy

### Kai partition

`KAI_SECRET` remains unencrypted and physically last. It must have no initial
`/etc/fstab` entry and must not be desktop-automounted during the encrypted-base
installation or certification period.

If a later reviewed configuration mounts it, the baseline mount policy is:

```text
nodev,nosuid,noexec,umask=077
```

Its permanent reservation does not make it suitable for credentials, private
keys, LUKS backups, recovery archives, personal records, or other sensitive data
unless the individual file is independently encrypted.

### EFI System Partition

The ESP must not contain private signing keys or LUKS recovery material. Linux
mount permissions must restrict modification to root. A promoted boot artifact
must be copied atomically where practical, verified after the copy, and followed
by an updated private ESP archive and manifest.

## Post-installation network-boot policy

After certification, the internal signed boot path must be first in the normal
boot order. Network boot remains available only through deliberate firmware
selection for rescue and maintenance.

The Acer's installer service must be stopped when it is not actively required.
Destructive installer entries must never remain the default PXE choice, and no
unattended timeout may select them. Read-only inspection may remain available as
a pinned rescue generation.

## Added destructive-installation gates

Before any command can erase signatures, create a partition table, format a
filesystem, or create a LUKS container, all of the following must be true:

1. the A720 internal disk has been identified by a private stable fingerprint,
   exact byte size, logical and physical sector sizes, and current GPT report;
2. the exact aligned start and end sectors for the 2 GiB ESP, LUKS2 partition,
   and final 5 GiB Kai partition have been recorded and independently checked;
3. the proposed LVM allocation records the fixed 20 GiB swap LV and 5%
   unallocated VG reserve;
4. all removable storage, including the protected Kingston backup and original
   installation material, is physically detached;
5. the signed destructive-installer UKI has a pinned hash, a verified signature,
   an embedded immutable command line, and a verified build manifest;
6. the physically booted environment proves its own generation identity before
   offering a destructive command;
7. no target filesystem is mounted, no target-backed swap is active, and no
   unexpected block device is present;
8. recovery artifacts and independent backups have been hash-checked and
   test-read; and
9. the target identity and geometry are rechecked immediately before the first
   write.

A mismatch at the final recheck cancels the destructive action. Device names such
as `/dev/sda` are never sufficient identity.

## Revised installation sequence

The approved high-level order is:

1. complete read-only disk inventory and preserve its evidence;
2. build and prove the signed installer UKI under Secure Boot;
3. detach all removable storage;
4. re-identify the internal disk and verify the exact sector map;
5. create GPT, ESP, final Kai partition, and the intervening LUKS2 partition;
6. create volume group `darkstar`, 20 GiB swap LV, ext4 root LV, and retain 5%
   free extents;
7. install a minimal Debian base with stock signed fallback first;
8. enroll the operational passphrase and generated recovery key;
9. create and protect the initial GPT, LUKS, and ESP recovery evidence;
10. certify repeated stock cold boots and manual unlocks;
11. restore A720 platform support one layer per physical boot;
12. build, sign, and test the Darkstar UKIs and Prettyboot path;
13. build and test the narrow hibernation-under-lockdown kernel;
14. certify repeated hibernate-resume cycles and the stock fallback; and
15. create and rehearse the new encrypted-architecture recovery set.

## Final acceptance additions

The rebuild is incomplete until physical evidence confirms all of the following:

- Secure Boot accepts the signed loader and signed UKI chain;
- the custom UKI signature covers the intended kernel, initramfs, microcode,
  metadata, and command line;
- external unsigned command-line or initramfs changes cannot alter the custom
  boot path;
- the stock Debian fallback remains bootable with its normal lockdown policy;
- the custom kernel reports integrity lockdown active;
- required signed modules load and unsigned modules are rejected;
- encrypted root and the dedicated swap LV unlock only through approved keys;
- both the operational passphrase and offline recovery key have been tested;
- the 20 GiB swap LV supports repeated hibernate-resume cycles through the
  custom signed path;
- the 5% VG reserve remains unallocated;
- the 2 GiB ESP and physically final 5 GiB `KAI_SECRET` partition remain healthy;
- GPT, LUKS, ESP, UKI, and kernel-build recovery evidence is complete and
  test-readable;
- the new recovery environment boots without beginning a restore; and
- normal boot no longer depends on an active PXE installer service.

## Failure policy

A failed gate is evidence, not permission to weaken Secure Boot, disable
lockdown, remove recovery keys, consume the VG reserve, repurpose `KAI_SECRET`,
attach protected media blindly, or improvise against an unverified disk node.
Return to the last proved artifact or layout, preserve the failure evidence, and
change one major variable per physical test.
