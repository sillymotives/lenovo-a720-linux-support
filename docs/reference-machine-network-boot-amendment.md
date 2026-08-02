# Reference machine: network-provisioned encrypted rebuild amendment

Status date: 2026-08-02

This amendment supersedes the removable-media recovery, in-place filesystem
shrink, and swap-partition repair stages in
`reference-machine-secureboot-hibernation-recovery-plan.md`.

The A720 will be rebuilt from bare metal over the wired network. The required
outcome is deliberately strict:

1. the Darkstar graphical standalone GRUB path ("prettyboot");
2. UEFI Secure Boot with a verifiable signed loader, kernel, and early-userspace
   chain;
3. encrypted system storage with a dedicated encrypted 20 GiB swap area; and
4. reliable suspend-to-disk hibernation.

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

### Protected backup device

The Kingston DataTraveler containing ReaR backups is recovery infrastructure,
not installation media.

- Do not repartition it.
- Do not format it.
- Do not use it as network-boot workspace.
- Do not use it for bootloader experiments.
- Do not assume it occupies `/dev/sdb` or any other fixed device node.
- Keep it physically disconnected while the installer partitions the A720
  internal disk.
- Attach it only when recovery material is deliberately being read.

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

The preferred clean design is:

```text
A720 firmware with Secure Boot enabled
  -> signed shim
  -> signed Prettyboot loader
  -> signed stock Debian fallback or signed Darkstar UKI

internal disk
  -> EFI System Partition
  -> LUKS2 encrypted container
       -> encrypted root filesystem
       -> dedicated 20 GiB swap area
```

The exact LVM or direct-partition arrangement remains an implementation choice
until installer and initramfs behavior are tested.

The dependable unlock baseline is a manually entered LUKS passphrase. Any
hardware-assisted unlock is optional and secondary, and must retain a tested
recovery passphrase.

The trusted unlock prompt should live inside a signed Unified Kernel Image or an
equivalently authenticated early-boot environment. The stock Debian path must
remain available beside the custom path.

## Secure Boot and hibernation boundary

Stock Linux lockdown blocks hibernation under Secure Boot because an
unauthenticated hibernation image can re-enter kernel memory after the signed
boot chain has been verified.

Encrypted swap protects confidentiality, but ordinary sector encryption alone
does not prove freshness or cryptographic integrity of every resumed block. The
final design therefore requires an explicit threat-model review rather than the
assumption that encrypted swap resolves the entire policy conflict.

The candidate engineering route is a narrowly modified, owner-signed kernel or
UKI that:

- retains Secure Boot authentication;
- retains mandatory signed-module enforcement;
- retains lockdown protections unrelated to the chosen hibernation exception;
- resumes only after the encrypted storage mapping is activated by trusted early
  userspace; and
- installs alongside, not over, a stock Debian fallback kernel.

This is a deliberate security-policy choice, not merely a storage-layout change
or a single kernel toggle.

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
network address, or backup content belongs in this repository.

## Required network-boot behavior

The default network entry must be non-destructive. Merely selecting network boot
must never:

- start `rear recover` or another restore workflow;
- repartition or format the internal disk;
- mount the internal root filesystem read-write;
- attach, activate, reformat, or repartition the Kingston device;
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

- keep the Kingston device detached;
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

### Gate 2: clean encrypted Debian installation

- stage and pin the chosen installer generation;
- verify the A720 internal disk by stable identity;
- physically disconnect the Kingston backup device;
- erase and repartition only the A720 internal disk;
- create the EFI System Partition and the chosen LUKS2 storage layout;
- create encrypted root storage and a dedicated 20 GiB swap area;
- install a minimal Debian base and stock signed fallback path;
- do not restore machine-specific customization yet; and
- stop and preserve logs on any discrepancy rather than improvising.

### Gate 3: encrypted-base validation

- complete repeated cold boots through the stock Debian fallback;
- verify the intended authenticated early userspace and manual unlock path;
- verify encrypted root and swap activation;
- rebuild and inspect retained initramfs or UKI artifacts as appropriate;
- prove that the stock fallback remains bootable; and
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

### Gate 5: Prettyboot and signed boot chain

- rebuild Prettyboot from clean source;
- verify inherited and project SBAT rows;
- sign and verify the final EFI image;
- stage it without overwriting the stock Debian fallback;
- test it first through a one-shot boot mechanism;
- confirm the intended loader and kernel path; and
- promote it only after repeated cold-boot success.

### Gate 6: signed hibernation path

- build the narrowly modified Debian-derived kernel or UKI;
- retain mandatory module signatures and the chosen lockdown boundary;
- sign the kernel, early userspace, and required out-of-tree modules;
- install the custom path beside the stock fallback;
- verify encrypted swap resume configuration; and
- complete repeated controlled hibernate-resume tests before enabling the final
  Secure Boot policy.

### Gate 7: integrated certification

One complete physical test must demonstrate:

- Secure Boot enabled;
- the intended signed Prettyboot path visibly running;
- authenticated kernel and early userspace;
- encrypted root and swap unlocked through the intended path;
- required signed A720 platform modules loading;
- healthy desktop, graphics, audio, bezel controls, and shutdown transition;
- hibernation powering the machine fully off;
- resume restoring the original kernel boot ID and user session; and
- the stock Debian boot path and recovery environment remaining available.

## Failure policy

A failed gate is diagnostic information, not permission to weaken the Acer,
expose recovery data, improvise with the A720 disk, or attach the Kingston device
blindly. Restore the last proven boot generation, preserve logs, and change one
variable per test.

If firmware network boot is unreliable, retain the staged artifacts and return
to planning. Do not compensate by turning the protected Kingston backup device
into experimental boot media.
