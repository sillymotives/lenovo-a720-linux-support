# Reference machine: security incident response

Status date: 2026-08-02

This procedure applies to security and safety events affecting the A720 rebuild,
Acer provisioning host, boot artifacts, signing keys, recovery keys, protected
media, or audit evidence.

## Principles

- Stop before changing more state.
- Protect people, backups, and evidence before attempting repair.
- Do not continue a failed gate under a weaker control.
- Record direct observations separately from hypotheses.
- Use the stock Debian path or a known-good read-only generation as the default
  containment route.
- Change one major variable per recovery test.

## Severity

- **Critical:** suspected wrong-disk write, private signing-key compromise,
  destructive installer identity mismatch, or unrecoverable loss of the only
  key or backup copy.
- **High:** unexpected target writes, altered UKI or manifest, unknown trust
  anchor, recovery-key disclosure, or protected media attached during a
  destructive operation.
- **Medium:** unexpected PXE client, service exposure outside the isolated link,
  evidence hash mismatch, failed recovery rehearsal, or unexplained boot-order
  change.
- **Low:** documentation, timestamp, or evidence-index defects that do not alter
  the current technical state.

## Immediate containment matrix

| Event | Immediate action |
|---|---|
| Wrong target or geometry suspected | Do not issue another disk command. Photograph or capture the screen, record write counters, disconnect protected removable media, and power down only when further running state would increase risk. |
| Target write counters change during a read-only gate | Fail the gate, preserve counters and mounts, identify the writer from the current environment, and do not rerun until the cause is understood. |
| Boot generation or manifest mismatch | Stop the boot path, isolate the Acer, preserve served files and service configuration, and return to the previous pinned generation. |
| Signing key compromise or unexplained key access | Stop signing, disconnect the signing environment, preserve access evidence, inventory signed artifacts and enrolled trust stores, and begin replacement and revocation. |
| Recovery key or passphrase disclosure | Keep the machine powered down when practical, use another valid key to rotate affected LUKS keyslots, refresh protected header backups, and review all copies. |
| Unexpected MOK, firmware certificate, or SBAT state | Boot only the stock fallback or known-good rescue path, export the public trust inventory, and do not promote custom artifacts. |
| Unexpected PXE client or service exposure | Stop the installer service, disconnect the isolated cable, preserve lease counts and firewall state, and review the Acer before serving again. |
| Protected media lost, altered, or writable | Quarantine the device, do not use it for recovery, identify the last verified independent copy, and create a replacement only from trusted material. |
| Evidence digest or signature mismatch | Preserve both versions, mark the affected gate unverified, and reconstruct evidence only from independent raw sources. |

## Evidence capture

Create a private incident record containing:

- incident identifier and UTC time;
- reporter, operator, and decision owner;
- affected machine, generation, artifacts, and gate;
- current power, network, mount, swap, and removable-media state;
- hashes of relevant files and logs;
- photographs or screenshots where machine-readable capture is unavailable;
- containment actions in exact order;
- known and possible impact;
- recovery decision and residual uncertainty; and
- closure and follow-up evidence.

Do not put secrets, private keys, passphrases, recovery keys, raw disk serials, or
private network details in the public repository.

## Investigation

Investigation begins from the least invasive evidence:

1. compare pinned manifests and signatures;
2. inspect service, boot, kernel, and journal records;
3. inspect mounts, swap, holders, and write counters;
4. compare trust stores and certificate fingerprints;
5. compare current and previous-known-good ESP archives;
6. test recovery copies on a disposable target or loop-backed image; and
7. reproduce only after the original state and evidence have been preserved.

Filesystem repair, key rotation, repartitioning, and restore operations are
recovery actions, not investigation tools.

## Recovery

Recovery uses the smallest trusted layer that remains valid:

1. stock Debian signed fallback;
2. previous-known-good custom UKI;
3. pinned read-only network-rescue generation;
4. protected GPT, LUKS, ESP, and configuration evidence;
5. new encrypted-architecture recovery set; or
6. historical ReaR material as the final pre-rebuild parachute.

Every recovery action has a rollback point and verification criterion. A recovered
system is not returned to normal service until Secure Boot state, trust anchors,
disk identity, encrypted storage, fallback boot, and evidence integrity have been
rechecked.

## Key-compromise recovery

For an owner signing-key incident:

- generate replacement keys in a clean environment;
- enrol replacement public certificates through a reviewed process;
- rebuild and sign all affected artifacts from pinned sources;
- update SBAT where revocation requires it;
- remove or revoke the compromised trust anchor only after the replacement and
  stock fallback have been physically proved;
- prove the compromised artifact is rejected; and
- update the key inventory, recovery instructions, and incident record.

For a LUKS credential incident, rotate affected keyslots using a separately
verified valid key, verify both unlock paths, decide whether the header backup
must be replaced, and protect or destroy obsolete recovery copies.

## Closure

An incident closes only when:

- the cause and affected scope are recorded;
- containment is complete;
- recovery and fallback paths are physically tested;
- compromised or uncertain credentials and artifacts are rotated or retired;
- evidence is hash-indexed and stored independently;
- the relevant risk and control documents are updated; and
- the owner accepts any remaining uncertainty.

A closed incident may still create a major audit finding that blocks later gates.
