# Reference machine: audit and assurance plan

Status date: 2026-08-02

This document records the first-party audit method and compensating controls for
the Lenovo IdeaCentre A720 rebuild. It is aligned with the audit principles used
for information-security management-system audits: defined objectives, scope,
criteria, evidence, competence, impartiality, reporting, corrective action, and
follow-up.

It is not a claim of ISO certification. The project is a small owner-operated
technical programme, so complete organisational separation between designer,
operator, and auditor is not always possible. The machine owner has accepted that
constraint. It must remain visible rather than being disguised as independent
assurance.

## Audit objectives

The audit programme must determine whether the rebuild:

- protects the intended internal disk from accidental or unauthorised writes;
- preserves the protected backup and original installation media;
- authenticates the destructive installer and final custom boot chain;
- creates the approved GPT, LUKS2, LVM, filesystem, and swap layout;
- retains a stock Debian fallback and recoverable signing and storage keys;
- records enough evidence to reproduce, review, and recover the machine; and
- treats failures and residual risks explicitly rather than weakening controls.

## Scope

The audit scope includes:

- the Acer provisioning host and its temporary PXE services;
- every served installer and rescue generation;
- the A720 firmware, internal disk, ESP, Secure Boot path, UKIs, and kernel;
- the LUKS2 key hierarchy and offline recovery material;
- the custom hibernation-under-lockdown exception;
- the platform-support restoration sequence; and
- the evidence, review, incident, and corrective-action records.

Private keys, recovery keys, raw hardware identifiers, backup contents, and
machine-local network details remain outside the public repository. Their
existence and verification are recorded through hashes, fingerprints, or private
records.

## Audit criteria

Each gate is assessed against:

1. the current approved architecture documents in this repository;
2. the exact pinned boot-generation manifest;
3. the approved disk fingerprint and sector geometry;
4. the signed installer and UKI build manifests;
5. the applicable gate checklist and acceptance criteria;
6. the private risk register and accepted residual-risk decisions; and
7. the evidence-retention and incident-response requirements in this document.

A later amendment controls where documents conflict. Historical scripts and plans
must not silently regain authority.

## Roles and constrained independence

The minimum roles are:

- **asset and risk owner:** authorises scope, accepts residual risk, and decides
  whether a failed gate may be retried;
- **operator:** executes the approved commands and preserves evidence;
- **technical reviewer:** checks the exact sector map, signed installer UKI,
  custom kernel patch, and destructive command plan; and
- **auditor:** assesses evidence against the criteria and records findings.

One person may hold more than one role in this project. Where the operator,
designer, reviewer, or auditor is the same person, the gate record must say so.
The following compensating controls then become mandatory:

- calculations are regenerated from raw geometry rather than copied;
- hashes identify every reviewed artifact and record;
- CI and scripted checks are retained as separate evidence;
- destructive actions include an explicit pause and typed challenge;
- changed artifacts require a fresh review rather than inheriting approval; and
- unresolved uncertainty blocks the gate.

An independent human review is preferred for the sector map, installer UKI, and
kernel patch. When one is unavailable, a clean-room recalculation using an
independent method is the minimum substitute. Self-review may be recorded, but it
must not be described as independent review.

## Evidence record

Each gate must produce one private evidence record containing at least:

```text
gate identifier
UTC timestamp and time-synchronisation state
machine role and boot-generation identifier
operator and reviewer roles
artifact, script, manifest, and configuration hashes
private target-disk fingerprint reference
commands or procedure version used
observations and raw result locations
warnings, exceptions, and failed checks
decision: pass, conditional pass, fail, or not tested
residual-risk acceptance reference
next authorised gate
record hash and optional detached signature
```

The record must distinguish direct observation from inference. Screenshots or
photographs are supporting evidence, not substitutes for machine-readable output
where the latter is available.

## Evidence integrity and custody

- Gate evidence is written first to volatile or dedicated private storage, never
  to the target disk during a read-only gate.
- Each record and attachment receives a SHA-256 digest.
- A gate index lists every member by relative path, size, and digest.
- The completed bundle receives a detached signature when the signing process is
  available. Until then, store the index hash in a second independent location.
- Preserve at least two encrypted copies on independent media or systems.
- Do not store the only copy beside the machine it is intended to recover.
- Any later modification creates a new record version; previous evidence is not
  overwritten.

Evidence is retained for the life of the encrypted architecture and for at least
one complete replacement or decommissioning cycle afterward. Records containing
secrets or raw identifiers use the same retention period but remain private and
encrypted.

## Trusted time

Before the signed destructive-installer proof and immediately before the first
destructive write, record:

- UTC time;
- the active time source or synchronisation state;
- the Acer and A720 clock difference when both are available; and
- any known loss of trusted time.

Unavailable or unsynchronised time is recorded as an exception. It does not
invalidate cryptographic hashes, but it weakens chronology and requires explicit
review.

## Typed destructive challenge

No destructive command may run immediately after merely selecting a menu entry.
The final operator interaction must display:

- the stable target fingerprint hash;
- exact byte and sector geometry;
- the approved sector-map digest;
- the signed installer generation identifier and manifest digest;
- the list of visible whole disks; and
- confirmation that removable media is absent.

The operator must type a challenge derived from both the target fingerprint and
generation identifier. A simple `yes`, Enter key, unattended timeout, or device
name such as `/dev/sda` is insufficient.

## Risk register

| ID | Risk | Treatment and gate status |
|---|---|---|
| R-001 | Offline modification or replay of a hibernation image | Encrypted swap, signed UKI command line, narrow kernel exception, stock fallback, and explicit owner acceptance before enabling the custom path. Acceptance remains pending until the final patch is reviewed. |
| R-002 | Destructive write to the wrong disk | Stable fingerprint, exact geometry, independent sector calculation, removable-media detachment, visible-disk inventory, typed challenge, and immediate pre-write recheck. Gate blocking. |
| R-003 | Secure Boot or module-signing key compromise | Governed by the build and signing lifecycle document, offline backups, inventory, rotation, and incident response. Gate blocking before final signing. |
| R-004 | Acer or PXE service compromise, or an unexpected client | Isolated link, minimal service set, firewall review, pinned immutable generation, service sandbox review, active-client count, and service shutdown after use. Gate blocking before destructive PXE. |
| R-005 | Recovery artifacts are incomplete or unreadable | Hash check, complete read test, independent copies, GPT/LUKS/ESP evidence, and non-destructive recovery rehearsal. Gate blocking. |
| R-006 | Designer, operator, and auditor are not fully independent | Accepted by the owner with the compensating controls in this document. Reassess whenever an external reviewer becomes available. |
| R-007 | Audit evidence is altered or chronology is unclear | Hash-indexed bundles, detached signatures where available, independent copies, immutable versions, and trusted-time records. |
| R-008 | The authoritative preflight cannot run in the exact boot environment | `preflight-network-rescue.sh runtime` must pass inside the exact signed environment and its binary-path hashes must be preserved before that environment can authorise installation. Gate blocking. |

Risk ratings and acceptance decisions belong in the private evidence package when
they reveal machine-specific information. The public register records the risk
and treatment logic.

## Findings and corrective action

Findings use four states:

- **major:** a required control is absent or cannot achieve its objective;
- **minor:** a control exists but evidence, consistency, or implementation is
  incomplete;
- **observation:** no current nonconformity, but deterioration is plausible; and
- **opportunity:** a beneficial improvement not required for gate passage.

Every major or minor finding records an owner, action, target gate, evidence of
completion, and closure decision. A failed gate remains failed until new evidence
closes the finding. Verbal assurance does not close a finding.

## Audit cadence

Perform an audit review:

- before the signed destructive-installer proof;
- immediately before partitioning;
- after the encrypted base and both unlock paths are proven;
- after Prettyboot and the signed UKI chain are promoted;
- after the custom hibernation path is enabled;
- after the new recovery set is rehearsed; and
- after material updates to firmware, shim, GRUB, systemd, cryptsetup, the kernel,
  signing keys, disk layout, or recovery architecture.

## Current disposition

The current separate-kernel-and-initrd PXE generation is approved only for
read-only inventory. It does not satisfy the signed destructive-installer gate.
Destructive work remains prohibited until the runtime contract, target
immutability, exact disk map, signed UKI, recovery, review, and typed-challenge
controls have all produced passing evidence.
