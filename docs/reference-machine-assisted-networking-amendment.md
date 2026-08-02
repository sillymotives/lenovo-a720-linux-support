# Reference machine: remote-first installer control amendment

Status date: 2026-08-02

This amendment makes authenticated wired remote control a mandatory safety
control for the Lenovo IdeaCentre A720 rescue, inventory, installation, and early
recovery stages.

The control exists because long, high-consequence command sequences should not be
transcribed at a distant installer console. That is an interface hazard, not an
operator defect. The Acer provisioning host is therefore the normal control
surface for the A720 installer. The A720's local keyboard and display remain for
firmware selection, observation, and a short physical-presence challenge only.

Loss of the remote channel is a stop condition. It is never permission to replace
a reviewed script with improvised manual typing.

Nothing in this amendment authorises partitioning, formatting, LUKS creation,
filesystem creation, restoration, or EFI-variable changes. Remote access does not
weaken disk-identity, signed-generation, recovery, evidence, or destructive-action
gates.

## Control objective

For every installer generation, the operator must be able to:

1. select the intended UEFI network entry at the A720;
2. observe a concise local readiness screen;
3. connect from the Acer using one generation-aware command;
4. execute reviewed scripts and capture their output from the Acer;
5. stop safely if the link or authenticated session fails; and
6. confirm a destructive action, when later authorised, without manually
   transcribing the destructive command itself.

The remote terminal is the canonical administrative interface. The local A720
console must not be the primary place where long shell commands are entered.

## Required topology

The normal topology is:

```text
internet
   |
Acer Wi-Fi
   |
Acer operating system, browser, evidence store, and SSH client
   |
Acer wired interface
   |
isolated direct Ethernet cable
   |
A720 wired interface and rescue or installer environment
```

The A720 assistance channel uses only the direct wired link. The exact addresses,
interface names, client-key fingerprint, host-key fingerprint, and generation
identifier remain in private generation records.

The A720-side network must have:

- carrier on the intended wired interface;
- one reviewed private IPv4 address on the direct-link subnet;
- no Wi-Fi activation;
- no forwarding, bridging, masquerading, or routing role;
- no dependency on public DNS;
- no generally reachable listener; and
- no target-disk-backed log or state storage.

A default route is not required for remote assistance. Installer components and
public keys should be supplied by a generation-pinned HTTP service on the Acer.
The Acer may use its Wi-Fi connection to acquire and verify upstream packages,
but the A720 should receive only the locally served, approved material unless a
later gate explicitly approves restricted egress.

## Debian Installer network console

The preferred implementation for Debian Installer stages is Debian's
`network-console` component with `openssh-server-udeb`.

For the current read-only inventory generation, the component may be delivered by
a local, hash-pinned Debian installer mirror on the Acer. For the future signed
destructive-installer UKI, the required network-console packages, dependencies,
configuration, client public key, and helper scripts must be included in the
signed generation or fetched only from an equivalently authenticated local
source.

The network console must use public-key authentication. Password and
keyboard-interactive authentication must be disabled. The normal remote account
for Debian Installer is `installer`; another account or root login requires an
explicit generation record and equivalent restrictions.

## Authentication and listener restrictions

The SSH service must:

- bind only to the reviewed direct-link address;
- accept only the generation-approved client public key;
- disable password, keyboard-interactive, and empty-password authentication;
- disable agent, X11, TCP, stream-local, and tunnel forwarding;
- expose no unrelated service;
- keep logs and transient state in `/run` or another memory-backed filesystem;
- stop when the installer environment shuts down; and
- record its package versions, binary hashes, configuration hash, and listening
  address in the private generation evidence.

The corresponding private client key remains on the Acer with restrictive
permissions. No private SSH key belongs in the installer image, PXE tree, ESP,
`KAI_SECRET`, public repository, or target disk.

The Acer must pin the observed host key. A host-key change is rejected unless the
operator deliberately starts a new boot-instance record and verifies the new
fingerprint against the A720 local display or the signed generation manifest.
`StrictHostKeyChecking` must never be disabled.

## Remote-first operator workflow

The required workflow is:

1. boot the exact approved A720 generation;
2. wait for the local screen to show the generation ID, wired address, SSH host
   fingerprint, and a clear `REMOTE CONTROL READY` state;
3. run one reviewed connection helper on the Acer;
4. perform inventory, evidence collection, installer control, and script transfer
   through that session;
5. record the transcript and hashes in the private gate evidence;
6. use the A720 console only for firmware selection, visual cross-checks, and a
   short physical-presence token when required; and
7. stop immediately if the displayed identity and the Acer-side identity differ.

Commands longer than a short confirmation token must be transferred as reviewed
files, here-documents, or versioned scripts from the Acer. Screenshots are useful
supporting evidence, but machine-readable transcripts are authoritative where
available.

## Destructive-action separation

An SSH login is not destructive authorisation. Remote root access, if used in the
ephemeral environment, must not expose an unguarded partitioning command.

The first write still requires all existing controls, including:

- signed destructive-installer identity;
- stable target fingerprint and exact geometry;
- approved and independently recalculated sector-map digest;
- complete removable-media absence;
- zero unexpected mounts, swap, holders, and measured writes;
- visible whole-disk inventory;
- current recovery and evidence checks; and
- the typed challenge derived from both target and generation identity.

The reviewed destructive helper may be launched from the Acer. It must display
its complete target and generation evidence before asking for confirmation. When
physical presence is required, the A720 may display a short one-time token that
is entered at the Acer. The operator must never be asked to type the destructive
command itself at the A720 console.

## Required generation contents

Every remote-controlled rescue or installer generation must include or provide
from a pinned local source:

- the A720 wired-network driver and required firmware;
- network configuration and route-inspection tools;
- listener-inspection capability;
- Debian `network-console` and `openssh-server-udeb`, or a reviewed equivalent;
- the generation-approved client public key;
- a usable shell and file-transfer path;
- the complete network-rescue runtime contract;
- a readiness display showing generation, address, and host fingerprint;
- an in-memory transcript destination; and
- a generation manifest covering every supplied component.

The final signed destructive-installer UKI must authenticate the remote-control
configuration together with the kernel, initramfs, command line, metadata, and
other embedded resources.

## Assistance-channel evidence

Before a remote channel passes its gate, preserve privately:

- generation and boot-instance identifiers;
- A720 wired-interface carrier and address;
- complete route table;
- active listeners and their bind addresses;
- SSH package, binary, configuration, and authorised-key hashes;
- client-key and host-key fingerprints;
- Acer private-key permissions and known-hosts hash;
- a successful key-only non-interactive connection test;
- a successful interactive terminal and file-transfer test;
- transcript path and digest;
- local readiness-screen evidence; and
- proof that networking and login did not change target write counters.

## Current-generation boundary

The separate-kernel-and-initrd PXE generation used for read-only inventory is not
a signed destructive installer. Adding the network console improves control and
evidence collection, but does not authorise a target write.

The current generation may therefore be rewritten as an assisted read-only
inventory image using the official Debian kernel, a merged storage-capable
initramfs, a locally served Debian network-console component set, and a
hash-pinned Acer client key. It must retain a non-destructive default and an
unlimited menu timeout.

## Failure policy

If wired networking, local package delivery, SSH startup, key authentication,
host-key verification, terminal behaviour, file transfer, transcript capture, or
write-counter evidence fails, stop at the current non-destructive gate.

Repair and rebuild the generation from the Acer. Do not compensate by asking the
operator to perform a large manual command sequence on the A720.
