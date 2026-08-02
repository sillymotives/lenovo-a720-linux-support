# Lenovo A720 rebuild: ISO/IEC 27007-aligned first-party audit report

**Report ID:** A720-ISMS-2026-08-02-01  
**Audit date:** 2026-08-02  
**Report issued:** 2026-08-02T12:55:00Z  
**Repository:** `sillymotives/lenovo-a720-linux-support`  
**Audited change set:** draft pull request 6, branch `agent/document-secureboot-hibernation-recovery`  
**Audit type:** first-party design and readiness audit  
**Overall opinion:** qualified assurance  

## Status and disclaimer

This report is aligned with the audit principles and methods used by ISO/IEC
27007 for information-security management-system auditing. It is not an ISO
certification, accreditation statement, or independent third-party opinion.

The project is owner-operated. Design, implementation, operation, review, and
audit roles may be held by the same small team. That limitation is accepted and
must remain visible. Compensating controls include reproducible calculations,
pinned hashes, scripted gates, CI, immutable evidence versions, explicit pause
points, clean-room recalculation where possible, and a typed challenge before any
future destructive action.

## Audit objective

Determine whether the planned Lenovo IdeaCentre A720 rebuild provides a
controlled path to:

- preserve protected recovery and installation media;
- prevent writes to an unverified target disk;
- authenticate the installer and final boot chain;
- create the approved GPT, LUKS2, LVM, filesystem, and swap layout;
- retain Secure Boot, integrity lockdown, signed modules, and stock fallback;
- support controlled hibernation through a narrow, documented exception;
- preserve sufficient recovery and audit evidence; and
- stop safely when a required control or evidence item is absent.

## Scope

The audit covered:

- the Acer Aspire E1-530 provisioning host;
- the isolated direct Ethernet link;
- served PXE generations and their manifests;
- the A720 UEFI Secure Boot path;
- read-only Debian Installer inventory stages;
- the proposed signed installer UKI;
- the final ESP, LUKS2, LVM, root, swap, and `KAI_SECRET` layout;
- signing-key and build-provenance policy;
- recovery, evidence, incident, and failure procedures; and
- the remote-first installer-control design.

The audit did not inspect production private keys, recovery keys, raw disk
identifiers, backup contents, a completed signed installer UKI, a completed
custom hibernation kernel, or a final installed system.

## Audit criteria

The assessed criteria were:

1. the approved architecture and amendment documents in draft pull request 6;
2. the pinned official Debian payload hashes and generation manifests;
3. the protected-media rules;
4. the network-rescue and provisioning-host preflight contracts;
5. the signed-UKI, Secure Boot, lockdown, and fallback requirements;
6. the disk-identity, exact-geometry, and sector-map gates;
7. the recovery evidence and key-lifecycle requirements;
8. the remote-first human-error controls; and
9. the stated failure and residual-risk policies.

## Evidence reviewed

The audit reviewed public repository material and sanitised summaries of private
physical evidence. The physical evidence established that:

- official Debian signed shim and GRUB reached a custom UEFI PXE menu under
  Secure Boot;
- the official installer kernel and netboot initrd matched pinned SHA-256 values;
- the protected Kingston recovery device and SanDisk installation material were
  unmounted and kernel read-only on the provisioning host during staging;
- the early `BOOT_DEBUG=3` shell appeared before a usable keyboard stack;
- the later `BOOT_DEBUG=2` Debian Installer shell accepted keyboard input;
- `/target` was not mounted;
- the first netboot initrd exposed no block devices and lacked `ahci` and
  `ata_piix`;
- no target disk was selected, mounted, partitioned, formatted, or written;
- the official storage-capable hd-media initrd matched its pinned SHA-256 value;
  and
- the assisted remote-control design and client policy passed repository CI.

Publicly recorded official payload digests used during the evidence sequence:

```text
netboot.tar.gz  b4dfc1ede280b09cefe2ad850f1406004d300f782d416373fdbe300221b03b23
kernel           e7667ff961fcf0f872e2618a930454a6362ce58995f386431f60a5169c85f41a
netboot initrd   c8b67f68fb34d3bc91935564255b8f3404199f44fab227672e4861a62434dad5
hd-media initrd  0a973c5a884dd0e3468522fd840f2fcf19add4fbc16f300479af051c9fa6b8dc
```

## Positive control findings

### P-01: Destructive actions are gated by stable identity

The design rejects device names such as `/dev/sda` as sufficient identity. It
requires a private stable fingerprint, exact byte size, logical and physical
sector sizes, a recorded partition table, an independently recalculated sector
map, and an immediate pre-write identity recheck.

### P-02: Protected media is treated as infrastructure

The Kingston recovery device and original installation material are never
available as scratch space. They must be physically detached before the first
destructive write.

### P-03: The final boot architecture authenticates early userspace

The destructive installer and custom boot path must use a signed UKI or an
equivalent single authenticated EFI artifact. The authenticated object binds the
kernel, complete initramfs, command line, release metadata, microcode when used,
and project SBAT data.

### P-04: Recovery remains independent

The final ESP retains stock Debian fallback, current and previous-known-good
custom artifacts, and a recovery path. Promotion may not replace both the stock
fallback and previous-known-good custom path in one operation.

### P-05: Storage design is simple and recoverable

The approved physical layout is:

1. 2 GiB FAT32 EFI System Partition;
2. one LUKS2 system partition; and
3. one physically final 5 GiB FAT32 `KAI_SECRET` partition.

Inside LUKS2, volume group `darkstar` contains ext4 `root`, a fixed 20 GiB swap
LV, and 5 percent unallocated reserve. There is no separate plaintext `/boot`.

### P-06: Remote-first operation reduces transcription risk

The Acer is the normal administrative interface. Long or delicate commands are
transferred and executed as reviewed scripts over an authenticated isolated wired
channel. Loss of that channel is a stop condition rather than permission to
improvise at the A720 console.

### P-07: Failure is treated as evidence

A failed control does not authorise disabling Secure Boot, weakening lockdown,
consuming reserve space, attaching protected media blindly, or operating against
an unverified disk node.

## Findings and disposition

### M-01: Auditor independence is constrained

**Risk:** the same small team may design, implement, operate, and audit a control.

**Disposition:** accepted limitation with mandatory disclosure and compensating
controls. Self-review must not be described as independent review. Clean-room
recalculation and immutable artifact hashes are required where an independent
person is unavailable.

**Status:** accepted, monitored.

### M-02: The original rescue preflight could pass without kernel read-only enforcement

**Risk:** an inspection could be labelled read-only while the kernel still
allowed writes.

**Disposition:** the branch implementation now treats a writable target disk or
child partition as a failure, checks active holders, establishes write counters
before target inspection, and verifies cumulative zero writes after major stages.
CI guards against regression to a warning.

**Status:** implemented in code; physical retest in the exact signed environment
remains open.

### M-03: Runtime dependencies were not proven in the installer environment

**Risk:** an authoritative preflight could be unavailable when needed.

**Disposition:** a runtime-contract mode records required executable paths and
hashes. The future signed installer must include and physically prove the complete
runtime contract.

**Status:** code implemented; signed-environment proof open.

### M-04: Signing-key lifecycle was initially incomplete

**Risk:** poorly controlled signing keys could undermine otherwise strong Secure
Boot controls.

**Disposition:** the branch now defines key roles, clean generation, encrypted
offline copies, trust-anchor inventory, signing ceremony, build provenance, SBAT,
rotation, revocation, compromise response, and retirement.

**Status:** policy implemented; production ceremony and evidence open.

### N-01: Residual risk requires explicit acceptance

The custom hibernation path retains integrity lockdown but deliberately permits a
narrow hibernation exception. Encrypted swap protects confidentiality but does
not make every resumed block fresh or independently authenticated.

**Status:** treatment defined; owner acceptance remains required before enabling
the custom path.

### N-02: Evidence custody requires physical application

The branch defines gate records, hashes, an index, versioning, trusted-time state,
detached signatures when available, and two independent encrypted copies.

**Status:** process defined; first complete physical gate bundle open.

### N-03: PXE service hardening requires environment-specific evidence

The provisioning-host inventory can record systemd sandboxing, capabilities,
unit hashes, generation permissions, manifest state, and lease counts without
publishing client identifiers.

**Status:** tooling implemented; service-specific evidence open.

### N-04: Custom-build provenance requires a first attestation

The policy requires source revision, source signatures, compiler and linker
versions, dependencies, configuration, patch, build host, binary hashes, signer
fingerprints, SBOM or package manifest, and reproducibility comparison.

**Status:** policy implemented; first signed UKI and kernel attestations open.

### N-05: Incident response has not been exercised

The branch defines response procedures for key compromise, trust-store changes,
installer mismatch, provisioning-host compromise, evidence tampering, and lost
recovery media.

**Status:** procedure implemented; exercise open.

### N-06: Trusted time and retention require operational evidence

The branch defines time-state recording and evidence retention for the life of
the encrypted architecture plus a replacement or decommissioning cycle.

**Status:** policy implemented; operational proof open.

## Audit decisions

| Activity | Decision |
|---|---|
| Continue storage-capable read-only inventory | Approved |
| Rebuild the read-only generation with authenticated remote control | Approved |
| Treat the current separate kernel and initrd PXE path as destructive authority | Rejected |
| Build and test a signed destructive-installer UKI | Approved as non-destructive preparation |
| Partition, format, create LUKS, create filesystems, restore data, or change EFI variables | Not authorised |

## Conditions required before destructive authorisation

All of the following remain mandatory:

1. the physically booted signed environment passes its runtime contract;
2. authenticated remote control is available and evidenced;
3. the internal disk has a stable private fingerprint and exact geometry;
4. the aligned sector map is recorded and independently recalculated;
5. all removable media is physically absent;
6. no unexpected whole disk, target-backed mount, swap, or holder is present;
7. target write counters remain unchanged throughout the measured preflight;
8. the signed installer generation, manifest, signature, and embedded command
   line are verified;
9. recovery artifacts are test-readable and held in independent locations; and
10. the operator completes the typed challenge derived from both target and
    generation identity.

A mismatch cancels the operation.

## Overall conclusion

The A720 rebuild design provides strong preventive, detective, recovery, and
human-error controls for a single-machine owner-operated project. Its remaining
weaknesses are not hidden architectural shortcuts. They are explicit evidence
and implementation gates that have not yet been physically completed.

Qualified assurance is therefore appropriate:

- the design is suitable for continued non-destructive preparation and inventory;
- the documented remediation materially improves the control environment; and
- destructive installation remains correctly prohibited until the outstanding
  physical evidence is produced and accepted.

## Audit trail

The append-only public audit trail is maintained in
[`AUDIT_LOG.md`](AUDIT_LOG.md). Private receipts, raw identifiers, keys, network
addresses, and recovery materials remain outside the public repository.
