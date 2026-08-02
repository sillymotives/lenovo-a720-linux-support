# Reference machine: audit-remediation amendment

Status date: 2026-08-02

This amendment applies the implementable findings from the first-party,
ISO/IEC 27007-aligned audit of the A720 rebuild plan. It supplements the network,
partition, authenticated-boot, and recovery documents.

The current storage-capable PXE generation remains authorised only for read-only
inventory. Nothing in this amendment authorises partitioning, formatting, LUKS
creation, filesystem creation, restoration, or EFI-variable changes.

## Implemented controls

The authoritative network-rescue preflight now:

- provides a `runtime` mode that inventories required commands and records their
  executable paths and hashes;
- treats a writable target disk or writable target partition as a failure rather
  than a warning;
- rejects active block-device holders backed by the target, including active
  device-mapper or LVM paths visible through sysfs;
- establishes target write counters before identity and report setup;
- checks cumulative write counters after generation validation, target identity,
  target-use checks, and the final observation window; and
- cannot report a passing result when target immutability is absent.

Repository CI executes the runtime contract and guards against regression of the
read-only, holder, and write-counter checks.

The provisioning-host inventory can now inspect, when explicitly supplied:

- systemd sandbox and capability properties for the selected PXE service;
- the service-unit file hash;
- pinned-generation ownership, permissions, and manifest status; and
- the count of active DHCP lease records without printing client identifiers.

## Governance controls

The following documents are authoritative for the corresponding audit findings:

- `reference-machine-audit-assurance-plan.md` defines audit scope, evidence,
  constrained independence, clean-room review, risk treatment, trusted time,
  retention, and the typed destructive challenge;
- `reference-machine-build-signing-lifecycle.md` defines key generation, storage,
  inventory, build provenance, signing ceremonies, SBAT, rotation, revocation,
  and retirement; and
- `reference-machine-security-incident-response.md` defines containment,
  investigation, recovery, key-compromise response, evidence capture, and
  closure.

The owner has accepted the limited separation between designer, operator, and
auditor. That limitation is compensated by reproducible calculations, pinned
hashes, CI, explicit gates, immutable evidence versions, and clean-room review
where an independent person is unavailable.

## Conditions still requiring physical evidence

Before the network-rescue preflight becomes authoritative, `runtime` mode must
pass inside the exact physically booted signed environment. A successful CI run
on a generic runner proves the script contract and syntax, not the contents of
the future installer UKI.

Before destructive work, evidence must also prove:

1. target whole-disk and partition read-only state;
2. absence of target-backed mounts, swap, and holders;
3. stable private disk fingerprint and exact sector geometry;
4. zero target writes across the complete measured preflight;
5. exact aligned sector map and independent recalculation;
6. signed destructive-installer UKI identity and embedded command line;
7. protected-media absence and expected whole-disk inventory;
8. recovery artifact readability and independent copies;
9. signing-key lifecycle readiness; and
10. successful typed challenge derived from both disk and generation identity.

## Audit finding disposition

| Finding | Disposition |
|---|---|
| Constrained auditor independence | Accepted limitation with mandatory compensating controls; not represented as independent certification. |
| Writable target could pass preflight | Corrected in code and protected by CI; physical retest required. |
| Runtime dependencies not proven in installer | Runtime-contract mode implemented; exact signed-environment proof remains open. |
| Signing-key lifecycle incomplete | Policy implemented; production ceremony and private evidence remain open. |
| Evidence custody and retention incomplete | Audit plan implemented; first physical gate bundle remains open. |
| PXE service hardening evidence incomplete | Host inventory extended; service-specific evidence remains open. |
| Build provenance incomplete | Lifecycle requirements implemented; first signed UKI attestation remains open. |
| Incident response incomplete | Procedure implemented; no exercise has yet been performed. |

No finding is closed merely by documentation when its control objective requires
physical evidence. The remaining open items are gate conditions, not permission
to weaken or bypass them.
