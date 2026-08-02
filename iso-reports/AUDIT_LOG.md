# A720 rebuild public audit log

**Log ID:** A720-AUDIT-LOG  
**Opened:** 2026-08-02  
**Classification:** public, sanitised  
**Status:** active and append-only  

## Log rules

This file is the authoritative public chronology for the Lenovo IdeaCentre A720
secure rebuild audit. It records decisions, control changes, evidence summaries,
and finding status without publishing secrets or machine-specific identifiers.

The log follows these rules:

1. existing entries are not silently rewritten to make later results appear
   cleaner;
2. a factual correction is added as a new entry that identifies the superseded
   statement;
3. private evidence is referenced by class and result, not copied into Git;
4. pass, conditional pass, fail, accepted risk, and not-tested are distinct
   outcomes;
5. a documentation or CI change does not close a finding that requires physical
   evidence;
6. no entry in this log authorises destructive work unless it explicitly says so;
   and
7. private keys, recovery keys, raw disk identifiers, network addresses, backup
   contents, and LUKS metadata backups are never recorded here.

## Role statement

The machine owner is the asset and risk owner. Design, implementation, operation,
technical review, and audit may be performed by the same small owner-operated
team. This is recorded as constrained first-party assurance, not independent
certification. Reproducible calculations, pinned hashes, CI, explicit gates,
clean-room recalculation, immutable evidence versions, and physical pause points
are used as compensating controls.

## Chronological records

### AL-001: Rebuild safety boundary established

**Date:** 2026-08-02  
**Actors:** asset owner, operator, technical designer  
**Evidence:** project handoff, protected-media inventory, repository planning  
**Result:** pass  

The following non-negotiable boundaries were recorded:

- the Kingston DataTraveler contains recovery material and is never scratch space;
- the SanDisk Cruzer contains original installation material and is not
  interchangeable with the Kingston device;
- both removable devices must be physically detached before destructive target
  work;
- a Linux device node is not sufficient disk identity;
- Secure Boot is not disabled as a shortcut;
- unsigned iPXE is not accepted; and
- the target disk must be proved by stable identity, size, sector geometry, and
  current partition evidence before any write.

**Decision:** non-destructive provisioning work may continue. Destructive work is
closed.

### AL-002: Isolated UEFI PXE proof passed

**Date:** 2026-08-02  
**Evidence:** private terminal receipt and physical display observation  
**Result:** pass  

An isolated direct Ethernet path from the Acer provisioning host to the A720
successfully delivered official Debian signed shim and GRUB. The A720 reached the
custom proof menu under Secure Boot and displayed the expected proof marker.

This established:

- DHCP and TFTP reachability on the isolated link;
- UEFI x86-64 network boot;
- acceptance of Debian-signed shim and GRUB;
- GRUB configuration and module availability; and
- a safe return path without touching target storage.

**Decision:** signed network boot is proven for inspection. It is not yet an
authenticated destructive installer.

### AL-003: Official installer payloads pinned

**Date:** 2026-08-02  
**Evidence:** official Debian artifacts, private staging receipt, generation
manifest  
**Result:** pass  

The following SHA-256 digests were pinned and verified:

```text
netboot.tar.gz  b4dfc1ede280b09cefe2ad850f1406004d300f782d416373fdbe300221b03b23
kernel           e7667ff961fcf0f872e2618a930454a6362ce58995f386431f60a5169c85f41a
netboot initrd   c8b67f68fb34d3bc91935564255b8f3404199f44fab227672e4861a62434dad5
```

The kernel signature was inspected and the staged generation manifest verified.
No preseed, automatic partition recipe, `auto=true`, early command, or late
command was present.

**Decision:** generation approved for read-only installer inventory.

### AL-004: Protected removable media quarantine verified

**Date:** 2026-08-02  
**Evidence:** private host inventory  
**Result:** pass with persistence warning  

Both protected USB devices were unmounted and kernel read-only on the Acer during
staging.

**Warning:** kernel read-only state does not persist across unplug, replug, or
reboot.

**Decision:** the devices remain protected for non-destructive staging. Physical
detachment is still mandatory before destructive target work.

### AL-005: Cold PXE link behaviour investigated

**Date:** 2026-08-02  
**Evidence:** private DHCP/TFTP logs and boot observation  
**Result:** investigated, workaround accepted  

A cold A720 boot selected the IPv4 network entry but fell through to internal
boot. Provisioning-host logs showed no firmware PXE traffic before the A720's
internal operating system raised Ethernet carrier.

A warm reboot, a short pause in the firmware boot menu, and deliberate selection
of the Realtek IPv4 entry successfully restored PXE operation.

**Decision:** use the documented warm-boot procedure until a firmware-level cause
is better understood. This is an availability issue, not evidence of target-disk
failure.

### AL-006: Earliest debug shell rejected for inventory use

**Date:** 2026-08-02  
**Evidence:** physical display observation  
**Result:** fail safely  

`BOOT_DEBUG=3` stopped in the earliest BusyBox shell before a usable keyboard
stack was available. Multiple keyboards and ports did not provide input.

The A720 was powered off while still in RAM-based early userspace. No target disk
had been selected or mounted.

**Decision:** `BOOT_DEBUG=3` is unsuitable for this workflow. Replace it with
`BOOT_DEBUG=2` and retest.

### AL-007: Later Debian Installer shell established

**Date:** 2026-08-02  
**Evidence:** private generation receipt and physical console test  
**Result:** pass  

A cloned generation replaced `BOOT_DEBUG=3` with `BOOT_DEBUG=2` while retaining
low priority, text frontend, and rescue mode. The manifest verified and the later
Debian Installer shell accepted keyboard input.

**Decision:** use the later installer shell for read-only inventory until remote
control is available.

### AL-008: Initial block-device inventory found no visible disk

**Date:** 2026-08-02  
**Evidence:** physical shell output  
**Result:** safe negative result  

The tiny installer shell did not contain `lsblk`. `/sys/block` and
`/proc/partitions` were empty. `/target` was not mounted.

**Decision:** do not infer disk loss or disk failure. Investigate missing storage
modules without writing to storage.

### AL-009: Missing SATA host drivers identified

**Date:** 2026-08-02  
**Evidence:** physical `modprobe` output  
**Result:** root cause identified  

The netboot initrd did not contain `ahci` or `ata_piix`. `sd_mod` did not report a
load error, but no SATA host driver was available to expose a device.

**Decision:** the disk has not been proved absent. The initrd is too small for
local-storage inventory. Abort the installer safely and stage an official
storage-capable environment.

### AL-010: Storage-capable hd-media generation staged

**Date:** 2026-08-02  
**Evidence:** private staging receipt and active PXE contract  
**Result:** pass  

The official Debian hd-media initrd was downloaded, checked against official
`SHA256SUMS`, tested for gzip integrity, added to a cloned immutable generation,
and activated through the proven PXE service.

Pinned digest:

```text
hd-media initrd  0a973c5a884dd0e3468522fd840f2fcf19add4fbc16f300479af051c9fa6b8dc
```

The first menu entry remained manual, non-destructive, low priority, text-mode,
and rescue-enabled. The previous netboot generation and proof entries remained
available.

**Decision:** storage-capable read-only inventory approved. Destructive work
remains closed.

### AL-011: ISO/IEC 27007-aligned first-party audit issued

**Date:** 2026-08-02  
**Evidence:** audit report A720-ISMS-2026-08-02-01  
**Result:** qualified assurance  

The audit found strong architecture and control intent, with major open items in
independence disclosure, read-only enforcement, runtime proof, and signing-key
lifecycle. Minor findings covered residual-risk acceptance, evidence custody,
PXE hardening, build provenance, incident response, trusted time, and retention.

**Decision:**

- read-only inventory approved;
- signed-installer preparation approved as non-destructive work;
- the original preflight rejected as authoritative until corrected and retested;
- partitioning, formatting, LUKS creation, restoration, and EFI-variable changes
  not authorised.

### AL-012: Read-only preflight controls remediated in draft PR 6

**Date:** 2026-08-02  
**Evidence:** branch commits and CI run 58  
**Result:** implementation pass, physical proof pending  

The branch implementation was changed to:

- fail when the whole target or any child partition is not kernel read-only;
- detect target-backed holders;
- establish write counters before identity and report setup;
- verify cumulative zero writes after major stages;
- expose a runtime-contract mode; and
- prevent regression through CI checks.

CI run 58 passed.

**Decision:** code finding M-02 is remediated in design and CI. It remains open
until physically retested inside the exact signed environment.

### AL-013: Audit governance and lifecycle controls documented

**Date:** 2026-08-02  
**Evidence:** draft PR 6 documentation and CI  
**Result:** implementation pass, operational proof pending  

The branch added:

- a first-party audit and assurance plan;
- explicit constrained-independence handling;
- a risk register and residual-risk gates;
- evidence custody, trusted time, retention, and typed-challenge rules;
- build and signing-key lifecycle controls;
- SBAT, rotation, revocation, and retirement rules; and
- security incident-response procedures.

**Decision:** governance findings are addressed in policy. Findings requiring
physical evidence, ceremonies, attestations, or exercises remain open.

### AL-014: Remote-first installer control adopted

**Date:** 2026-08-02  
**Evidence:** remote-first amendment, Acer connection helper, CI runs 61 and 64  
**Result:** design pass, physical implementation pending  

Authenticated wired remote control was made a mandatory human-error control.
Long or delicate command sequences must be transferred and executed from the
Acer rather than transcribed at the A720 console.

The preferred Debian Installer implementation is `network-console` with
`openssh-server-udeb`, public-key authentication, generation-pinned known-hosts,
no password fallback, and no generally reachable listener. The connection helper
defaults to the Debian Installer `installer` account.

CI run 64 passed after the wording and helper were aligned.

**Decision:** the current storage-only generation may be replaced by an assisted
read-only generation. Loss of the assistance channel is a stop condition.

### AL-015: Dated audit report committed to main

**Timestamp:** 2026-08-02T12:55:00Z  
**Evidence:** main commit `eb68971d5e9fc991e4ad8487539ae3b4d18af0f8`  
**Result:** pass  

The sanitised report
`iso-reports/2026-08-02-iso-27007-aligned-audit-report.md` was committed directly
to `main`.

**Decision:** the public report becomes the dated baseline audit opinion. Later
changes must be recorded in this log and, when material, in a new report or
addendum rather than silently changing the historical opinion.

### AL-016: Current gate state at log creation

**Timestamp:** 2026-08-02T12:55:00Z  
**Evidence:** consolidated public and private evidence summary  
**Result:** controlled hold  

Current physical and procedural state:

- the A720 is powered off;
- the storage-capable read-only PXE generation is staged;
- the assisted read-only generation has not yet been physically staged and
  tested;
- the internal disk identity and sector geometry have not yet been captured;
- the signed destructive-installer UKI has not yet been built or boot-proved;
- the production signing ceremony has not occurred;
- protected removable media has not yet reached the final physical-detachment
  gate; and
- no destructive disk action is authorised.

**Next authorised work:** rewrite and stage the assisted read-only PXE generation,
boot it, prove the key-only remote channel, and collect read-only disk inventory
evidence.

## Finding status register

| Finding | Control objective | Current status | Closure evidence required |
|---|---|---|---|
| M-01 | Honest treatment of constrained independence | Accepted limitation, monitored | Role disclosure and compensating controls in each relevant gate record |
| M-02 | Kernel-enforced target immutability | Implemented in branch, open physically | Exact signed environment passes read-only and zero-write preflight |
| M-03 | Complete authoritative runtime | Implemented in branch, open physically | Runtime-contract output and hashes from the physically booted signed image |
| M-04 | Controlled signing-key lifecycle | Policy implemented, ceremony open | Private ceremony record, trust inventory, protected copies, signer fingerprints |
| N-01 | Explicit hibernation residual-risk acceptance | Treatment defined, acceptance pending | Owner acceptance tied to reviewed kernel patch and final test evidence |
| N-02 | Evidence integrity and custody | Process defined, first bundle open | Indexed, hashed, independently copied physical gate evidence |
| N-03 | PXE host and service hardening | Tooling implemented, evidence open | Unit, sandbox, capability, firewall, generation, and client evidence |
| N-04 | Reproducible build provenance | Policy implemented, attestation open | Signed installer and kernel build attestations and reproducibility comparison |
| N-05 | Incident response readiness | Procedure implemented, exercise open | Recorded tabletop or technical exercise and corrective actions |
| N-06 | Trusted time and retention | Policy implemented, operational proof open | Time-state record and retained first complete evidence bundle |
| N-07 | Authenticated remote administration | Design and client policy implemented | Physical key-only network-console session, pinned host key, transcript, zero-write proof |

## Destructive-authorisation register

| Action | Status |
|---|---|
| Boot official signed PXE proof menu | Authorised and completed |
| Boot read-only Debian Installer environments | Authorised |
| Stage an assisted read-only generation | Authorised |
| Collect read-only disk identity and geometry | Authorised after target appears |
| Build and inspect a signed installer UKI | Authorised as non-destructive preparation |
| Delete signatures or partition tables | Not authorised |
| Create or modify GPT partitions | Not authorised |
| Format ESP, root, swap, or `KAI_SECRET` | Not authorised |
| Create LUKS2, LVM, or filesystems | Not authorised |
| Restore backup data | Not authorised |
| Modify EFI variables for installation | Not authorised |

## Required next log entry

The next entry must record the assisted-generation staging result and include:

- generation identifier and manifest digest;
- official component and local-mirror verification result;
- SSH server and configuration hashes;
- authorised client-key fingerprint reference;
- proof that no private key entered the served generation;
- active PXE contract;
- CI or local validation result; and
- explicit confirmation that no target-disk command was executed.
