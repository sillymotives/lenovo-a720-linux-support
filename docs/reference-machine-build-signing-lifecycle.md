# Reference machine: build and signing lifecycle

Status date: 2026-08-02

This document governs source provenance, reproducible build evidence, Secure Boot
signing, module signing, certificate inventory, rotation, revocation, and
retirement for the A720 rebuild. It contains no private keys or machine-specific
secret material.

## Scope

The lifecycle applies to:

- the signed destructive-installer UKI;
- the Darkstar Prettyboot EFI image;
- current and previous-known-good Darkstar UKIs;
- the custom Debian-derived hibernation kernel;
- required out-of-tree kernel modules; and
- any certificate enrolled through firmware, shim, MOK, or another trust store.

The stock Debian fallback remains vendor-managed and is inventoried rather than
re-signed locally.

## Key roles

Separate signing roles are preferred:

1. an EFI/UKI signing key for owner-controlled EFI artifacts;
2. a module-signing key for required out-of-tree modules; and
3. any temporary test key used only before final promotion.

Combining roles requires a recorded risk decision because one compromised key
would then affect a larger trust boundary. Private keys must never be stored in
the public repository, on the ESP, on `KAI_SECRET`, inside a served PXE tree, or
in an unencrypted backup.

## Generation ceremony

Before generating a production key:

- use a clean, fully updated environment whose OS and package versions are
  recorded;
- verify the entropy source and record how randomness was obtained;
- select an algorithm and key size supported by the enrolled firmware, shim,
  signing tools, and verification tools;
- record the intended key role, owner, creation time, validity period, and
  rotation trigger;
- generate the private key directly into encrypted storage with restrictive
  permissions; and
- export only the public certificate needed for enrolment and verification.

The private record includes the public-certificate fingerprint. It must not
include the private key itself in an audit log.

## Storage and backup

- Keep the operational private key offline except during an approved signing
  ceremony.
- Protect every key copy with strong encryption and physical access control.
- Maintain at least two independent encrypted recovery copies in separate
  locations.
- Test that a recovery copy can be opened before relying on it.
- Record the media identifier privately without publishing raw serial numbers.
- Do not leave decrypted key material in shell history, temporary directories,
  swap, screenshots, or ordinary terminal logs.
- Securely remove temporary decrypted copies after verification.

Where practical, signing occurs on a dedicated offline system. If the Acer is
used, its state, network disconnection, mounted filesystems, processes, package
versions, and temporary-key cleanup become part of the ceremony evidence.

## Certificate and trust-anchor inventory

Maintain a private inventory containing:

- key role and certificate subject;
- SHA-256 certificate fingerprint;
- serial number and validity dates;
- creation and enrolment dates;
- every firmware, shim, MOK, kernel, or application trust store containing it;
- every active artifact signed by it;
- current status: test, active, retiring, revoked, compromised, or destroyed; and
- replacement and revocation references.

The inventory is reviewed before every promotion and after firmware resets,
MOK changes, motherboard service, or Secure Boot database changes.

## Pinned build inputs

Every custom build records and verifies:

- upstream and Debian source revisions;
- source-package and repository signature status;
- all local patches and configuration deltas;
- compiler, linker, binutils, build-system, signing-tool, and compression-tool
  versions;
- the build host OS, architecture, kernel, locale, and relevant environment;
- build dependencies and their exact package versions;
- microcode and initramfs inputs;
- the embedded kernel command line, release metadata, and SBAT rows;
- the source and output SHA-256 manifests; and
- the CI or local validation results.

A package manifest or software bill of materials is preserved for the build
environment. Network-fetched inputs must be pinned and signature- or hash-checked
before use.

## Reproducibility and independent verification

The preferred release process performs two builds from the same pinned inputs in
clean environments and compares the unsigned outputs. Where byte-for-byte
reproducibility is not achieved, the record explains expected differences and
verifies the security-relevant embedded sections independently.

The technical reviewer receives:

- source revision and patch set;
- configuration delta;
- input manifest;
- unsigned and signed output hashes;
- embedded UKI section report;
- SBAT report;
- PE signature verification output; and
- the intended promotion and rollback paths.

A changed input, patch, command line, SBAT generation, certificate, or output hash
invalidates the previous approval.

## Signing ceremony

An approved signing ceremony must:

1. identify the exact unsigned artifact by hash;
2. verify the build manifest and reviewer decision;
3. confirm the intended key role and certificate fingerprint;
4. ensure the signing environment exposes no unnecessary network or writable
   removable storage;
5. sign the artifact without modifying unreviewed embedded content;
6. verify the resulting PE or module signature with an independent verification
   command;
7. re-extract and compare UKI sections, command line, metadata, and SBAT;
8. create a signed-artifact manifest and ceremony record;
9. copy the artifact into a new immutable generation rather than overwriting the
   previous-known-good generation; and
10. clean up decrypted key material and temporary files.

The person signing and the person reviewing should differ where practical. When
they do not, the constrained-independence controls in the audit plan apply.

## SBAT management

- Every project component has an identified SBAT product and generation.
- Increment a generation only through a reviewed change that records what is
  being revoked or superseded.
- Do not reuse a retired generation for a materially different binary.
- Preserve the inherited Debian rows and verify the final embedded bytes.
- Record the active and previous-known-good SBAT data beside the artifact hashes.

## Promotion

Promotion is staged:

- test keys and artifacts first use one-shot boot selection;
- the stock fallback and previous-known-good custom artifact remain untouched;
- the copied artifact is verified in place on the ESP;
- a new ESP archive and manifest are created;
- repeated cold boots pass before normal boot order changes; and
- the destructive installer is removed or disabled after its purpose is complete.

No promotion is authorised merely because signing succeeded.

## Rotation and expiry

Rotate a key when:

- its planned validity or review period ends;
- the algorithm or key size is no longer approved for the environment;
- a storage copy is lost or its confidentiality is uncertain;
- an operator with access no longer requires that access;
- trust-store changes make continued use ambiguous; or
- compromise is suspected.

Rotation includes generating and enrolling the replacement, signing test
artifacts, proving both fallback and replacement paths, retiring old artifacts,
and updating every inventory and recovery instruction. Do not remove the old
trust anchor until the replacement path and recovery path are physically proven.

## Compromise and revocation

Suspected compromise immediately stops signing and promotion. Preserve evidence,
disconnect the signing environment, inventory affected artifacts and trust
stores, generate a replacement in a clean environment, and follow the incident
response plan.

Revocation may require one or more of:

- removing an enrolled MOK or firmware certificate;
- incrementing project SBAT generations;
- replacing affected UKIs, loaders, kernels, and modules;
- restoring the stock Debian fallback as the only trusted custom-independent
  path; and
- rotating recovery evidence and instructions.

Revocation is not considered complete until a cold boot proves the compromised
artifact is rejected and the recovery path still works.

## Retirement and destruction

A retired key remains protected until every artifact and trust store depending on
it has been inventoried and migrated. Destruction of private-key copies is
recorded by copy and location. Public certificates, fingerprints, manifests, and
verification records remain available for historical audit and recovery.
