# Reference machine: network-provisioned encrypted rebuild amendment

Status date: 2026-08-02

This amendment supersedes the removable-media recovery, in-place filesystem
shrink, and swap-partition repair stages in
`reference-machine-secureboot-hibernation-recovery-plan.md`.

The later `reference-machine-authenticated-boot-storage-amendment.md` fixes the
remaining UKI, lockdown, LUKS2, LVM, key-recovery, and post-installation policy.
Where its implementation details conflict with this document, the later
hardening amendment controls.

The A720 will be rebuilt from bare metal over the wired network. The required
outcome is deliberately strict:

1. the Darkstar graphical standalone GRUB path ("prettyboot");
2. UEFI Secure Boot with a verifiable signed loader, kernel, command line, and
   early-userspace chain;
3. encrypted system storage with a dedicated encrypted 20 GiB swap area; and
4. reliable suspend-to-disk hibernation while retaining integrity lockdown on
   the custom signed path.

A result that silently trades away one of these requirements is incomplete.

## Machines and roles

### Target: Lenovo IdeaCentre A720

- Debian 13 remains the intended operating-system family.
- Network boot has been deliberately enabled in firmware.
- The internal disk may be erased and repartitioned only after the read-only
  network-boot and recovery gates pass.
- The modified firmware splash resides on the motherboard and is independent of
  the disk rebuild.
- The current installation remains evidence and a fallback source until the
  destructive installation gate is explicitly crossed.

### Provisioning host: Acer Aspire E1-530

- The Acer is the PXE and installation-services host.
- It serves a controlled installer and recovery environment over the wired
  network.
- It is persistent infrastructure, not a disposable staging box.
- Changes to its working desktop, boot path, networking, and services must be
  measured, documented, and reversible.
- Private addresses, interface names, DHCP details, credentials, and
  machine-local paths do not belong in this public repository.

### Protected backup and installation media

The Kingston DataTraveler containing ReaR backups is recovery infrastructure,
not installation media. Original installation material is also protected source
media, not scratch space.

- Do not repartition either device.
- Do not format either device.
- Do not use either device as network-boot workspace.
- Do not use either device for bootloader experiments.
- Do not assume either device occupies `/dev/sdb` or any other fixed node.
- Keep all removable storage physically disconnected while the installer
  partitions the A720 internal disk.
- Attach protected media only when its contents are deliberately being read.

## Proven state before the rebuild

The following results were physically demonstrated before choosing the clean
network rebuild:

- 16 GiB of physical RAM was installed and detected correctly;
- the Darkstar firmware splash survived disk-side bootloader experiments;
- the standalone Prettyboot path rendered its ignition-ring theme during a
  one-shot boot;
- Debian booted through the stock signed shim path as a fallback;
- the machine hibernated to a 20 GiB swapfile and resumed with the same kernel
  boot ID; and
- the A720 platform driver, bezel-volume bridge, audio path, graphics work,
  Plymouth transition, and related machine-specific fixes had working
  implementations or recovery notes.

The old swapfile proves that the hardware and resume path can work. It is not the
intended final storage architecture.

## Target storage and boot architecture

The fixed clean design is:

```text
A720 firmware with Secure Boot enabled
  -> signed shim
  -> signed Prettyboot loader
  -> signed stock Debian fallback or signed Darkstar UKI

internal disk
  -> 2 GiB EFI System Partition, FAT32
  -> LUKS2 encrypted system partition
       -> LVM volume group `darkstar`
            -> ext4 logical volume `root`
            -> dedicated 20 GiB logical volume `swap`
            -> 5% of volume-group extents left unallocated
  -> 5 GiB FAT32 `KAI_SECRET` partition, physically last
```

There is no separate plaintext `/boot`, `/home`, `/var`, or `/tmp` partition.
The `/boot` directory lives inside encrypted root. Firmware-readable kernels and
early userspace are delivered as signed UKIs on the ESP.

The dependable unlock baseline is a manually entered LUKS passphrase plus a
separately generated high-entropy recovery key. FIDO2 is optional only after the
manual and recovery paths pass cold-boot tests. TPM-assisted automatic unlock is
not part of the initial build.

## Authenticated installer boundary

The read-only PXE proof may use separately transferred official kernel and initrd
artifacts with pinned hashes. That proof does not authorize partitioning.

Before any destructive installer entry exists, the installer kernel, complete
initramfs, microcode when present, immutable command line, release metadata, and
project SBAT data must be bound into one signed UKI or an equivalently
authenticated EFI artifact.

The signed destructive installer must:

- have a pinned versioned generation and manifest;
- have its signature and embedded resources inspected on the Acer;
- boot physically under Secure Boot before receiving any destructive command;
- prove its generation identity from the booted environment;
- reject external unsigned initramfs, command-line, or addon substitution; and
- remain an explicit menu choice with no unattended destructive timeout.

## Secure Boot and hibernation boundary

Stock Linux lockdown blocks hibernation under Secure Boot because a restored
image can re-enter kernel memory after the signed boot chain has been verified.

Encrypted swap protects confidentiality, but ordinary sector encryption alone
does not prove freshness or cryptographic integrity of every resumed block. The
final design therefore treats hibernation as an explicit threat-model decision.

The final engineering route is a narrowly modified, owner-signed Debian-derived
kernel and UKI that:

- retains Secure Boot authentication;
- retains integrity lockdown rather than disabling it wholesale;
- retains mandatory signed-module enforcement and module-version checks;
- permits hibernation only through a small reviewed exception;
- requires an explicit project-specific opt-in parameter embedded in the signed
  UKI command line;
- resumes only after trusted early userspace unlocks the intended LUKS2
  container and activates the dedicated swap LV; and
- installs alongside, not over, an unmodified stock Debian fallback kernel.

The exact source revision, patch, configuration delta, build procedure, binary
hash, and signer fingerprint must be preserved. The stock fallback keeps its
normal lockdown behavior even if that path refuses hibernation.

## Recovery material

Private recovery material exists outside Git:

- the original Linux installation material;
- a ReaR rescue ISO;
- the matching ReaR backup archive;
- copies of EFI System Partition contents, including the known-good Prettyboot
  payload; and
- local rollback and maintenance notes.

The rescue ISO has passed local checksum and structural inspection. It contains
both legacy and UEFI boot paths, signed EFI components, and an interactive rescue
environment. The separate backup archive is not embedded in the ISO.

The ReaR environment is a parachute, not the preferred installer. Its automatic
recovery path is destructive and would reproduce the captured storage layout,
not create the new encrypted architecture. It must never be the default PXE menu
entry.

The backup archive and original installation material must still be hash-checked
and test-read before the A720 disk is erased. No recovery image, archive, private
key, certificate, signed deployment binary, filesystem UUID, MAC address,
network address, credential, firmware image, or backup content belongs in this
repository.

After the final encrypted architecture passes certification, create a new
recovery set for the GPT, LUKS2, LVM, ESP, UKI, and key-recovery design and
perform a non-destructive boot and restore rehearsal.

## Required network-boot behavior

The default network entry must be non-destructive. Merely selecting network boot
must never:

- start `rear recover` or another restore workflow;
- repartition or format the internal disk;
- mount the internal root filesystem read-write;
- attach, activate, reformat, or repartition protected removable media;
- alter the EFI System Partition;
- change EFI variables or the permanent boot order;
- run filesystem repair automatically; or
- accept an unattended destructive timeout choice.

The first entry must be a read-only inspection environment. Installer and
recovery entries must require explicit operator selection and stop at a clear
confirmation boundary before issuing disk-changing commands.

Every served generation must be pinned and versioned. Every boot artifact must
have a recorded SHA-256 digest in a separate manifest that is checked on the Acer
and again from the booted environment.

After final certification, the internal signed path returns to first place in the
normal boot order. Network boot remains deliberate F12-only rescue access, and
the Acer's installer service is stopped when not actively required.

## Provisioning-host preparation

Before the A720 attempts network boot:

- inventory the Acer's operating system, firmware mode, storage capacity,
  network interfaces, routes, DHCP context, listening ports, firewall posture,
  PXE-related packages, and potentially conflicting services;
- do not print or commit hardware addresses in the public report;
- choose the physical topology deliberately: shared router or switch, or direct
  Ethernet;
- determine whether router DHCP can be configured before choosing DHCP,
  proxy-DHCP, or an isolated direct-link design;
- place installer and rescue artifacts in dedicated versioned directories;
- create and verify manifests for every delivered artifact;
- keep the immediately previous known-good generation available;
- ensure the default entry is read-only;
- disable automatic restore, automatic partitioning, and writable automounts;
- verify that private backup material is not exported anonymously; and
- keep all Acer configuration changes reversible.

TFTP, HTTP, iPXE, PXELINUX, GRUB network boot, NFS, and proxy-DHCP are
implementation choices. Use the smallest service set that satisfies the A720
firmware and selected installer. Prefer a minimal first stage followed by
checksummed transfer of larger artifacts over HTTP where practical.

## Effect on the current preflight tool

`tools/preflight-secureboot-hibernation.sh` was written for the abandoned
in-place repair plan. It remains in the draft as review history, but it is not
authoritative for the clean network rebuild.

Before physical use, the checks must be separated into at least two roles:

1. an Acer provisioning-host inventory and artifact-manifest gate; and
2. an A720 target/rescue preflight that proves boot-generation identity, target
   disk identity, protected-device absence, and non-destructive behavior.

The existing script must not authorize repartitioning. Its assumptions about the
old root filesystem, old swap partition, local ISO paths, archive paths, and
`/dev/sdb` are obsolete under this amendment.

## Revised execution gates

Do not proceed to the next gate until evidence for the current gate is attached
to the private maintenance log.

### Gate 0: private artifact verification

- verify the selected Debian installer artifacts and their source;
- verify the ReaR ISO against its separate checksum manifest;
- verify the complete backup archive digest and readability;
- verify the original installation material;
- preserve the known-good Prettyboot and EFI recovery copies; and
- record the exact artifact generations without publishing private identifiers.

### Gate 1A: Acer provisioning-host inventory

- run the read-only host inventory before installing or starting PXE services;
- record wired interfaces, routes, DHCP context, storage capacity, relevant
  packages, ports, firewall posture, and conflicting services;
- choose the physical network topology;
- preserve the Acer's existing working configuration; and
- approve a reversible service design before changing networking.

### Gate 1B: server-side boot-generation gate

- stage a versioned read-only inspection generation;
- verify all artifact hashes against the separate manifest;
- inspect the boot menu and prove the default entry is non-destructive;
- confirm that no secret or credential is embedded in a served file;
- confirm that private backup material is not anonymously exported; and
- retain the previous known-good generation.

### Gate 1C: A720 read-only network-boot proof

- keep protected removable media detached from the A720;
- select network boot through the firmware's temporary boot menu;
- boot the read-only inspection entry;
- confirm keyboard, display, wired networking, and rescue shell operation;
- verify the delivered generation identity;
- identify the internal disk without mounting it read-write;
- confirm that no restore, partitioning, formatting, filesystem repair, or
  writable automount ran; and
- return to the installed Debian system without writing the disk or EFI
  variables.

### Gate 1D: recovery rehearsal

- network boot the same pinned inspection or rescue generation;
- prove that the ReaR environment remains interactive by default;
- verify that the private backup source is reachable only through the intended
  restricted path;
- verify the archive digest and complete archive readability;
- do not start automatic or interactive recovery;
- do not mount the A720 root filesystem read-write; and
- return without changing the target disk or backup source.

### Gate 1E: signed destructive-installer proof

- build the installer UKI from pinned inputs;
- verify its embedded kernel, initramfs, command line, metadata, and SBAT;
- verify its signature and manifest on the Acer;
- boot it physically under Secure Boot;
- prove its identity from inside the booted environment;
- confirm that external unsigned substitutions cannot alter it; and
- stop before any disk-changing command.

### Gate 2: clean encrypted Debian installation

- verify the A720 internal disk by private stable identity and exact byte and
  sector geometry;
- record and independently check the exact aligned sector map;
- physically disconnect every removable storage device;
- erase and repartition only the verified A720 internal disk;
- create the 2 GiB ESP, middle LUKS2 partition, and physically final 5 GiB Kai
  partition;
- create VG `darkstar`, ext4 LV `root`, dedicated 20 GiB LV `swap`, and retain
  5% of VG extents unallocated;
- install a minimal Debian base and stock signed fallback path;
- enroll a manual passphrase and generated recovery key;
- create protected GPT, LUKS-header, ESP, and layout recovery evidence; and
- stop and preserve logs on any discrepancy rather than improvising.

### Gate 3: encrypted-base validation

- complete repeated cold boots through the stock Debian fallback;
- verify the intended authenticated early userspace and manual unlock path;
- test both the operational passphrase and recovery key;
- verify encrypted root and swap activation;
- prove the stock fallback remains bootable;
- verify the 5% VG reserve remains free; and
- do not introduce Prettyboot, the custom kernel, or platform extensions until
  the minimal base is stable.

### Gate 4: layered platform restoration

Restore and test one layer at a time:

- A720 WMI and bezel support;
- audio and volume bridge behavior;
- graphics and desktop configuration;
- Plymouth and shutdown transitions;
- machine-specific services and permissions; and
- remaining documented platform fixes.

One major variable changes per physical boot test.

### Gate 5: Prettyboot and signed UKI chain

- rebuild Prettyboot from clean source;
- verify inherited and project SBAT rows;
- build current, previous-known-good, and stock-recovery UKI paths;
- verify the embedded resources, PE signatures, and manifests;
- stage them without overwriting the stock Debian fallback;
- test the custom path first through a one-shot boot mechanism;
- confirm the intended loader, UKI, command line, and kernel path; and
- promote it only after repeated cold-boot success.

### Gate 6: hibernation under integrity lockdown

- build the narrow Debian-derived kernel patch;
- retain integrity lockdown, mandatory module signatures, and module versioning;
- require the signed embedded hibernation opt-in parameter;
- preserve source, config delta, patch, binary hash, and signer fingerprint;
- install the custom path beside the stock fallback;
- verify encrypted swap-LV resume configuration; and
- complete repeated controlled hibernate-resume tests.

### Gate 7: integrated certification

One complete physical test must demonstrate:

- Secure Boot enabled;
- the intended signed Prettyboot path visibly running;
- authenticated UKI kernel, early userspace, and command line;
- integrity lockdown active on the custom kernel;
- encrypted root and swap unlocked through the intended path;
- required signed A720 platform modules loading and unsigned modules rejected;
- healthy desktop, graphics, audio, bezel controls, and shutdown transition;
- hibernation powering the machine fully off;
- resume restoring the original kernel boot ID and user session;
- the stock Debian path retaining normal lockdown and remaining bootable;
- the ESP, VG reserve, and final Kai partition remaining correct; and
- the new recovery environment booting without beginning a restore.

## Failure policy

A failed gate is diagnostic information, not permission to weaken the Acer,
expose recovery data, disable lockdown, improvise with the A720 disk, consume the
VG reserve, or attach protected media blindly. Restore the last proven boot
generation, preserve logs, and change one variable per test.

If firmware network boot is unreliable, retain the staged artifacts and return
to planning. Do not compensate by turning protected removable media into
experimental boot media.
