# Lenovo A720 rebuild: IEC 31010:2019-aligned risk assessment report

**Report ID:** A720-RISK-2026-08-02-01  
**Assessment date:** 2026-08-02  
**Report issued:** 2026-08-02T13:00:00Z  
**Repository:** `sillymotives/lenovo-a720-linux-support`  
**Assessed change set:** draft pull request 6 and associated private physical-test evidence  
**Assessment type:** first-party technical and operational risk assessment  
**Overall decision:** destructive work remains prohibited; assisted read-only staging and inventory remain authorised  

## Status and standard reference

This report applies risk-assessment techniques consistent with IEC 31010:2019,
*Risk management — Risk assessment techniques*, in support of the process and
principles described by ISO 31000:2018.

The published reference number is **IEC 31010:2019**, although it is part of the
joint ISO/IEC risk-management toolbox and is commonly discussed alongside the
ISO 31000 family. IEC 31010:2019 is the current published second edition at the
issue date of this report and is under review.

This report is not certification, accreditation, a safety case, or an independent
third-party opinion. It is a documented first-party assessment for a small,
owner-operated project. Ratings are decision aids, not mathematical predictions.

Official references:

- <https://www.iso.org/standard/72140.html>
- <https://www.iso.org/standard/65694.html>

## Decision objectives

The assessment supports four decisions:

1. whether the present PXE environment may continue to be used for read-only
   inventory;
2. whether an assisted, remotely controlled read-only generation may be staged;
3. what conditions must be satisfied before any destructive installer is built
   or used; and
4. which residual risks require explicit owner acceptance rather than silent
   treatment as resolved.

The protected outcomes are:

- preservation of the intended internal disk until the destructive gate is
  explicitly opened;
- preservation of the Kingston recovery device and original installation media;
- authentication of the installer and final boot path;
- creation of the approved GPT, LUKS2, LVM, filesystem, swap, and recovery layout;
- reliable recovery from boot, encryption, build, and operator failures; and
- prevention of long, error-prone command transcription at the A720 console.

## Scope

Included:

- the Acer provisioning host and isolated wired PXE link;
- signed Debian shim, GRUB, kernel, initramfs, and future installer UKI;
- the A720 internal disk, GPT, LUKS2 container, LVM, filesystems, and swap;
- authenticated remote installer control;
- signing keys, recovery keys, LUKS header backups, and build provenance;
- custom hibernation under integrity lockdown;
- recovery, evidence, audit, and incident-response controls; and
- human factors associated with a small owner-operated team.

Excluded from public detail:

- raw disk serials, WWNs, filesystem identifiers, and network addresses;
- private SSH, Secure Boot, recovery, or LUKS keys;
- recovery archive contents and LUKS header backups; and
- unpublished machine-specific evidence.

## Information used

The assessment uses:

- the architecture and amendments in draft pull request 6;
- the ISO/IEC 27007-aligned audit report and public audit log;
- private PXE staging receipts and physical boot observations;
- official Debian artifact hashes and signatures;
- the known protected-media boundaries; and
- the current physical state, in which no destructive target operation has been
  authorised or performed.

Important evidence gaps at the issue date are:

- the storage-capable environment has not yet produced the final disk inventory;
- the assisted read-only generation has not yet been physically staged or tested;
- the future signed installer UKI has not been built or boot-proved;
- the production signing-key ceremony has not occurred;
- the final sector map has not been calculated from observed geometry; and
- the new encrypted-architecture recovery set has not been created or rehearsed.

## Techniques selected

The following complementary techniques were chosen because no single method is
sufficient for the mixture of human, cryptographic, storage, networking, and
recovery uncertainty in this project.

| Technique | Application in this report | Reason selected |
|---|---|---|
| Structured what-if analysis | Identifies abnormal states and stop conditions | Effective for a changing, staged technical procedure |
| Failure modes and effects analysis | Ranks failure modes across installer functions | Exposes detection weakness as well as consequence and occurrence |
| Bow-tie analysis | Examines the top event of an unapproved destructive write | Makes preventive and recovery barriers visible together |
| Consequence-likelihood matrix | Prioritises inherent, current, and target residual risks | Provides a common decision language without false numerical precision |
| Barrier analysis | Tests whether controls are independent, effective, and vulnerable to degradation | Important where several controls can fail for the same underlying reason |
| Decision-tree logic | Defines go, hold, and stop outcomes for the destructive gate | Prevents ambiguous interpretation during execution |
| Checklists | Supports repeatable physical and cryptographic gate verification | Appropriate for high-consequence, low-frequency work |

## Risk criteria

### Consequence

| Rating | Description |
|---|---|
| 1 | Negligible: no permanent loss, trivial local rework |
| 2 | Minor: recoverable interruption or limited rework |
| 3 | Moderate: material delay, rebuild work, or limited data/control exposure |
| 4 | Major: prolonged outage, trust compromise, or difficult recovery |
| 5 | Severe: irreversible target or recovery loss, persistent compromise, or inability to recover the intended system |

### Likelihood

| Rating | Description |
|---|---|
| 1 | Rare: requires several independent barriers to fail |
| 2 | Unlikely: plausible under specific abnormal conditions |
| 3 | Possible: credible during the project without additional treatment |
| 4 | Likely: expected to occur in repeated execution under current conditions |
| 5 | Almost certain: already occurring or inherent in the current method |

### Risk level

The score is consequence multiplied by likelihood.

| Score | Level | Decision rule |
|---|---|---|
| 1-4 | Low | Proceed with normal monitoring |
| 5-9 | Moderate | Proceed only with named controls and owner visibility |
| 10-14 | High | Treatment and evidence required before the affected gate |
| 15-25 | Critical | Activity prohibited until risk is reduced |

A low likelihood does not make a severe consequence harmless. Any residual risk
with consequence 5 requires tested recovery barriers and explicit owner
visibility even when its score is moderate.

## Consolidated risk register

`I` is inherent risk without the planned controls. `C` is the current residual
risk at the issue date. `T` is the target residual risk after the stated controls
are implemented and physically evidenced.

| ID | Risk event | I | C | T | Primary treatment and gate |
|---|---|---:|---:|---:|---|
| R-01 | A destructive operation targets the wrong whole disk | 20 Critical | 10 High | 5 Moderate | Stable private fingerprint, exact geometry, visible whole-disk inventory, physical media detachment, typed challenge, immediate pre-write recheck |
| R-02 | Protected recovery or installation media is overwritten | 15 Critical | 5 Moderate | 5 Moderate | Never use as workspace; physical detachment before destructive work; verify absence after reboot |
| R-03 | A modified or unauthenticated initramfs, command line, or installer executes | 15 Critical | 10 High | 5 Moderate | Signed installer UKI binding kernel, initramfs, command line, metadata, microcode, and SBAT; pinned manifest and physical Secure Boot proof |
| R-04 | Manual transcription causes an incorrect high-consequence command | 16 Critical | 12 High | 4 Low | Remote-first control, reviewed transferred scripts, short physical-presence token, no long destructive typing at the A720 |
| R-05 | The remote assistance channel is spoofed or accepts the wrong peer | 12 High | 8 Moderate | 4 Low | Isolated wired link, key-only authentication, generation-pinned known-hosts, no password fallback, no forwarding or public listener |
| R-06 | Required storage, networking, shell, or inspection runtime is absent | 12 High | 9 Moderate | 3 Low | Runtime-contract inventory and hashes inside the exact signed generation; build-time and boot-time failure on missing tools |
| R-07 | The sector map or LVM allocation is calculated incorrectly | 15 Critical | 10 High | 5 Moderate | Calculate from observed geometry, independently regenerate, hash the approved map, display exact boundaries before write |
| R-08 | Secure Boot signing keys are compromised, lost, or misused | 10 High | 10 High | 5 Moderate | Documented generation ceremony, encrypted offline copies, trust inventory, restricted use, rotation, revocation, and retirement procedure |
| R-09 | Recovery evidence exists but is incomplete, corrupt, or unreadable | 15 Critical | 10 High | 5 Moderate | Indexed and hashed evidence bundle, two encrypted independent copies, test-read GPT/LUKS/ESP material, recovery rehearsal |
| R-10 | A hibernation image is modified or replayed while the custom exception is enabled | 12 High | 8 Moderate | 8 Moderate | Encrypted swap, signed immutable command line, narrow kernel patch, stock fallback, explicit residual-risk acceptance before enablement |
| R-11 | A compromised or irreproducible build introduces an unreviewed installer or kernel | 15 Critical | 10 High | 5 Moderate | Pinned source and dependencies, compiler and toolchain record, binary hashes, signed build attestation, reproducibility comparison |
| R-12 | PXE or assistance services are exposed to an unexpected client or network | 12 High | 8 Moderate | 4 Low | Direct cable, interface binding, firewall and service sandbox, expected-client evidence, service stopped when unused |
| R-13 | LUKS passphrases, recovery keys, or header backups are lost or become unusable | 10 High | 10 High | 5 Moderate | Operational passphrase, generated recovery key, protected header backup, cold-boot tests, refreshed records after keyslot change |
| R-14 | Common-mode error arises because design, operation, review, and audit are performed by the same small team | 12 High | 8 Moderate | 8 Moderate | Honest role disclosure, clean-room recalculation, immutable hashes, scripted checks, pause points, CI, explicit owner acceptance |
| R-15 | Cold PXE behaviour or link loss prevents the intended boot | 8 Moderate | 4 Low | 2 Low | Warm-boot workaround, deliberate firmware selection, retained local fallback, stop rather than reinterpret as disk failure |
| R-16 | The unencrypted `KAI_SECRET` FAT partition is treated as confidential storage | 9 Moderate | 6 Moderate | 3 Low | No initial automount, restrictive mount options, explicit warning, independent file encryption for any sensitive content |
| R-17 | The SSH session drops during a destructive operation and leaves state ambiguous | 12 High | 12 High | 4 Low | Destructive work executed by a locally complete, reviewed helper; remote link used to launch and observe, not as an instruction stream; durable in-memory status and idempotent recovery procedure |
| R-18 | Power interruption occurs during partitioning, installation, or boot-artifact promotion | 8 Moderate | 8 Moderate | 4 Low | Stable mains power, no unnecessary devices, pre-write recovery evidence, atomic promotion where possible, repeatable installation and fallback path |

## Priority treatment groups

### P0: before the next assisted read-only boot

- R-04 manual transcription;
- R-05 remote peer authentication;
- R-06 runtime completeness; and
- R-12 service exposure.

Required evidence is a generation-pinned, key-only remote console over the direct
wired link, runtime-contract output, listener and route evidence, host-key
pinning, transcript capture, and unchanged target write counters.

### P1: before any destructive write

- R-01 wrong target;
- R-02 protected-media loss;
- R-03 unauthenticated installer;
- R-07 geometry error;
- R-08 signing-key failure;
- R-09 unusable recovery evidence;
- R-11 build provenance failure;
- R-13 encryption-key or header loss;
- R-17 remote-session interruption; and
- R-18 power interruption.

No P1 risk may remain High or Critical at the destructive gate.

### P2: before custom hibernation is enabled

R-10 remains a deliberate Moderate residual risk even after treatment. It requires
an owner acceptance record linked to the exact reviewed kernel patch, signed UKI,
and repeated hibernate-resume evidence.

### P3: monitored and accepted project constraints

R-14 cannot be eliminated in a small owner-operated project. It is accepted only
with the listed compensating controls and must never be described as independent
assurance. R-15 and R-16 remain monitored operational risks.

## Structured what-if analysis

| What if... | Consequence | Required response |
|---|---|---|
| the target appears under a different `/dev` name? | Wrong-disk write | Ignore the device name; recompute and compare the stable fingerprint and geometry |
| an unexpected whole disk is visible? | Protected-media or wrong-target loss | Stop; identify or physically remove it before continuing |
| a protected USB was unplugged and reattached? | Kernel read-only protection may have reset | Re-inventory or detach it; previous read-only evidence is no longer valid |
| the served generation or manifest differs from the approved digest? | Untrusted installer state | Stop and restore the last proved immutable generation |
| an SSH host key changes for the same generation? | Possible interception or unintended environment | Reject the connection; do not delete known-hosts evidence as a workaround |
| a required binary or driver is missing? | Incomplete or misleading preflight | Fail the runtime contract and rebuild the generation |
| a target write counter changes during read-only inspection? | Target immutability has failed | Stop immediately, preserve evidence, and investigate before another boot |
| the sector-map recalculation differs by one sector? | Partition overlap, lost tail space, or invalid recovery evidence | Treat the map as unapproved and regenerate it from raw geometry |
| the remote session drops before a destructive helper starts? | Loss of control surface | Do not continue locally; restore the assistance channel |
| the remote session drops after a destructive helper starts? | Ambiguous progress | The local helper must finish or stop according to its own reviewed state machine and leave inspectable status in RAM |
| a recovery key works but the operational passphrase does not? | Single-path recoverability | Do not certify the encrypted base; repair and retest both paths |
| the stock fallback stops booting after custom UKI promotion? | Loss of independent recovery path | Roll back the custom promotion; certification fails |
| hibernation resumes without integrity lockdown active? | Broadened security exception | Reject the custom kernel build and return to stock fallback |
| trusted time is unavailable? | Weakened event chronology | Record the exception; rely on hashes for integrity and require explicit review |

## Bow-tie analysis: unapproved destructive storage operation

### Top event

A command capable of changing partition tables, encryption metadata, filesystems,
or boot state executes while the target identity, installer identity, layout, or
recovery state is not fully approved.

### Threats and preventive barriers

| Threat | Preventive barriers |
|---|---|
| Device-node drift or mistaken target | Stable fingerprint, exact byte and sector geometry, visible disk inventory, immediate pre-write recheck |
| Protected removable media remains attached | Physical detachment, absence check, no reliance on persistent kernel read-only state |
| Installer or initramfs is altered | Signed UKI, embedded command line, pinned manifest, Secure Boot proof, self-reported generation identity |
| Operator mistypes or truncates a command | Remote-first interface, transferred reviewed scripts, no long console transcription |
| Sector boundaries are stale or wrong | Independent regeneration, map digest, exact displayed start/end sectors |
| Active mounts, swap, LVM, or device-mapper holders exist | Kernel read-only enforcement, holder/mount/swap checks, write-counter baseline |
| Wrong remote peer controls the installer | Key-only SSH, generation-specific host pinning, direct link, no forwarding |
| A failed check is reinterpreted as permission to continue | Explicit stop policy, append-only audit record, no unattended destructive default |

### Consequences and recovery barriers

| Consequence | Recovery or mitigation barriers |
|---|---|
| Intended internal disk is erased incorrectly | Historical recovery set, new recovery plan, exact evidence of previous state |
| Recovery USB is destroyed | Physical detachment prevents common-cause loss; independent copies required |
| System becomes unbootable | Stock Debian fallback, previous-known-good UKI, network rescue, ESP archive |
| Encrypted data becomes inaccessible | Operational passphrase, offline recovery key, LUKS header backup, cold-boot tests |
| Boot trust becomes uncertain | Signer inventory, UKI hashes, SBAT record, rollback to stock signed path |
| Audit chronology becomes disputed | Append-only public log, private hashed evidence bundles, detached signatures when available |

### Barrier degradation factors

| Barrier | Degradation factor | Control |
|---|---|---|
| Kernel read-only state | Resets after reboot or device reattachment | Verify on every boot; physically detach protected media |
| Immutable PXE generation | Mutable active root or incomplete manifest | Clone-and-switch generations atomically; verify complete manifest |
| Human review | Same person and copied calculations | Clean-room regeneration using a separate method and recorded hashes |
| SSH host pinning | Ephemeral host key mistaken for expected change | Bind known-hosts evidence to generation identity and display fingerprint locally |
| Remote operation | Link loss during a streamed procedure | Execute complete local helpers with explicit states and recovery behaviour |
| Recovery archive | Backup exists but was never read | Test-read and rehearse against disposable media before certification |
| Signing key | Convenience copies spread across systems | Defined ceremony, encrypted offline custody, use log, rotation and revocation |

## Failure modes and effects analysis

Severity, occurrence, and detectability are rated from 1 to 5. A higher
detectability number means the failure is harder to detect before consequence.
The risk-priority number is used only to rank attention within this FMEA.

| Function | Failure mode | Effect | S | O | D | RPN | Required action |
|---|---|---|---:|---:|---:|---:|---|
| Recovery evidence | Backup is missing, corrupt, stale, or unreadable | No reliable restoration after failure | 5 | 3 | 4 | 60 | Two indexed copies, test-read, rehearsal, refresh after keyslot or layout change |
| Disk layout | Wrong sector boundary or alignment | Unbootable layout, overlap, or lost reserved partition | 5 | 3 | 3 | 45 | Independent recalculation and digest before write |
| Target selection | Wrong whole disk accepted | Irreversible data loss | 5 | 3 | 3 | 45 | Fingerprint plus geometry plus physical inventory and typed challenge |
| Signing lifecycle | Private key compromised or lost | Untrusted boot artifacts or inability to update | 5 | 2 | 4 | 40 | Offline custody, use records, backup, rotation and revocation plan |
| Hibernation exception | Modified or replayed image accepted | Compromised resumed state | 4 | 2 | 4 | 32 | Explicit residual-risk acceptance, narrow patch, signed command line, fallback |
| Installer trust | Separate initramfs changed without detection | Malicious or incorrect early userspace | 5 | 3 | 2 | 30 | Signed single-artifact installer UKI |
| Runtime | Storage or network module missing | Inventory failure or unsafe workaround pressure | 3 | 4 | 2 | 24 | Runtime contract and physically booted proof |
| Remote control | Wrong host accepted or authentication weakened | Unauthorised installer control | 4 | 2 | 3 | 24 | Pinned host key and public-key-only client policy |
| Protected media | Recovery device remains attached | Common-cause overwrite | 5 | 2 | 2 | 20 | Physical detachment and absence proof |
| Power and link | Interruption occurs mid-operation | Incomplete installation or ambiguous state | 4 | 2 | 2 | 16 | Local stateful helper, stable power, repeatable recovery path |

The highest FMEA priorities are recovery readability, sector-map correctness,
target selection, and signing-key lifecycle. Documentation alone does not close
any of them.

## Decision logic

### Assisted read-only generation

Proceed only when:

- the server-side generation and manifest verify;
- protected media remains unmounted and kernel read-only on the Acer;
- no destructive installer directive is present;
- the local component mirror and authorised public key are pinned;
- the SSH client helper retains host and user authentication; and
- the default menu entry is non-destructive with no unattended timeout.

A failed condition returns to staging. It does not authorise manual substitution.

### Read-only target inventory

Proceed only when:

- the physically booted generation identifies itself correctly;
- the remote channel is key-only and pinned;
- the whole target and child nodes are kernel read-only;
- no target-backed mount, swap, or holder is present; and
- cumulative target write counters remain unchanged.

Any change in write counters ends the gate and preserves evidence.

### Destructive installation

The destructive helper remains unavailable until all P1 treatments have physical
closure evidence. The final interaction must display the target fingerprint,
geometry, sector-map digest, installer generation, manifest digest, and visible
whole disks, then require a challenge derived from both target and generation
identity.

A mismatch, unknown value, extra disk, missing recovery artifact, or absent
remote channel produces **STOP**. There is no conditional branch that interprets
uncertainty as approval.

## Opportunity assessment

The assessment also identifies opportunities created by the treatments:

- remote-first operation reduces transcription risk and produces better evidence;
- a signed installer UKI can become a reusable authenticated rescue platform;
- immutable PXE generations simplify rollback and incident investigation;
- the 5% VG reserve provides controlled future capacity without changing GPT;
- current, previous, and stock UKIs improve recoverability during updates; and
- the audit and risk records create a repeatable pattern for other legacy systems.

These opportunities are accepted only where they do not weaken the stop rules.

## Monitoring and review triggers

Reassess affected risks when any of the following changes:

- target disk identity, capacity, or sector geometry;
- Debian installer, kernel, shim, GRUB, systemd, cryptsetup, or SSH versions;
- installer generation, initramfs composition, command line, or manifest;
- signing certificate, key custody, MOK, firmware trust store, or SBAT generation;
- partition map, LUKS keyslots, LVM allocation, swap, or recovery copies;
- PXE topology, firewall, service unit, client key, or host key;
- hibernation patch, resume path, lockdown state, or module-signing policy;
- audit finding status or incident evidence; or
- personnel or role assumptions used as compensating controls.

Mandatory review points are immediately before the first destructive write,
after encrypted-base installation, before custom UKI promotion, before enabling
hibernation, and after the first complete recovery rehearsal.

## Assessment conclusion

The architecture is capable of reducing the severe risks to controlled residual
levels, but several decisive treatments exist only in design at the issue date.
Current High or Critical residual risks include wrong-target destruction,
installer authentication, operator transcription, sector-map error, signing-key
lifecycle, recovery readability, build provenance, encryption-key recovery, and
remote-session interruption.

Therefore:

- staging and testing an assisted read-only PXE generation is authorised;
- authenticated remote read-only disk inventory is authorised after its own
  preflight passes;
- building and inspecting a signed installer UKI is authorised as
  non-destructive preparation;
- partition deletion, GPT creation, formatting, LUKS2 creation, LVM creation,
  restoration, and installation-related EFI-variable changes are **not
  authorised**; and
- the destructive gate may open only after this register is updated with physical
  closure evidence and no P1 risk remains High or Critical.

The central risk decision is intentionally blunt: uncertainty does not receive a
shell prompt. It receives a stop condition.
