# Reference machine: assisted-networking amendment

Status date: 2026-08-02

This amendment makes authenticated wired networking a mandatory usability and
safety requirement for the Lenovo IdeaCentre A720 read-only rescue environment,
the future signed destructive-installer UKI, and the initial encrypted-base
installation stage.

The operator must not be forced to retype long or delicate commands at the A720
console. The Acer provisioning host is therefore also the controlled remote
assistance terminal. Loss of the assistance channel is a stop condition, not a
reason to improvise commands manually.

Nothing in this amendment authorises partitioning, formatting, LUKS creation,
filesystem creation, restoration, or EFI-variable changes. Network access does
not weaken any existing disk-identity, signed-generation, recovery, or typed
challenge gate.

## Required topology

During rescue and installation, the normal topology is:

```text
internet
   |
Acer Wi-Fi
   |
Acer operating system and browser
   |
Acer wired interface
   |
isolated direct Ethernet cable
   |
A720 wired interface and signed rescue or installer environment
```

The A720 environment must use only the isolated wired link for remote assistance.
The exact private addresses, interface names, and public-key fingerprints remain
in private generation records rather than this public repository.

The installer-side network must have:

- link carrier on the intended wired interface;
- one reviewed private IPv4 address on the direct-link subnet;
- no default route;
- no DNS configuration;
- no Wi-Fi activation;
- no forwarding or routing role; and
- no dependency on internet access.

The Acer may retain its normal Wi-Fi internet connection. It must not bridge,
masquerade, or forward traffic from the A720 installer link unless a later
reviewed amendment explicitly requires it.

## Remote assistance service

The signed environment must contain and start an SSH-compatible server on the
isolated wired address. OpenSSH or Dropbear is acceptable when the exact package,
version, configuration, and binary hashes are recorded in the signed-generation
manifest.

The service must:

- bind only to the reviewed wired address;
- accept public-key authentication only;
- disable password and keyboard-interactive authentication;
- disable empty passwords;
- disable agent forwarding, X11 forwarding, TCP forwarding, and tunnelling;
- use a generation-specific authorised client public key;
- keep the corresponding private client key only on the Acer with restrictive
  permissions;
- write session and command evidence only to `/run` or another memory-backed
  location until deliberately exported; and
- stop when the rescue or installer environment shuts down.

The embedded authorised key is public material, but it is still generation
configuration and must be hash-pinned. No private SSH key belongs in the UKI,
PXE tree, ESP, `KAI_SECRET`, or public repository.

A host key may be generated in RAM at boot. The Acer helper must then pin the
first observed host key to a generation-specific known-hosts file and refuse a
changed key on later connections to the same generation. `StrictHostKeyChecking`
must never be disabled.

## Privilege model

Remote assistance may use either:

1. a dedicated temporary assistance account with reviewed privilege escalation;
   or
2. root public-key login in the ephemeral signed environment.

The selected model must be stated in the private generation record. In either
case, remote access alone must not make a destructive command immediately
available.

The first destructive write still requires all existing gates, including:

- signed installer identity;
- stable disk fingerprint and exact geometry;
- approved sector-map digest;
- removable-media absence;
- zero unexpected holders, mounts, swap, and writes;
- the displayed whole-disk inventory; and
- the typed challenge derived from both disk and generation identity.

The remote session may prepare and display the challenge. The operator must still
perform the explicit confirmation required by the approved destructive helper.
A generic `yes`, Enter key, unattended timeout, or SSH connection itself is not
confirmation.

## Required signed-environment contents

The future signed installer UKI must include, as pinned inputs:

- the A720 wired-network driver and required firmware;
- `ip` and route-inspection utilities;
- `ss` or an equivalent listener-inspection utility;
- the SSH server and its configuration;
- the public-key authorised-keys file;
- a usable shell and the complete network-rescue runtime contract;
- file-transfer capability through SSH; and
- sufficient terminal support for a persistent remote session.

The exact implementation may include a small session manager, but convenience
software must not silently add network listeners or write to the target disk.

## Operator workflow

The intended interaction is deliberately simple:

1. boot the exact signed rescue or installer generation;
2. let the A720 configure the isolated wired address and assistance service;
3. display the generation identifier, target address, and host-key fingerprint
   on the local console;
4. run one reviewed connection helper on the Acer;
5. conduct inventory and installation work through the remote terminal;
6. preserve the transcript and hashes in the private gate evidence; and
7. use the A720 console only for physical-presence checks and the final typed
   destructive challenge.

Long command blocks should be transferred as reviewed scripts or here-documents
from the Acer rather than retyped character by character on the A720.

## Assistance-channel evidence

Before the remote channel is accepted, record privately:

- A720 wired-interface carrier and IPv4 address;
- complete A720 route table proving the absence of a default route;
- active listeners and the exact address and port used by SSH;
- SSH server package, binary, and configuration hashes;
- authorised client-key fingerprint;
- observed host-key fingerprint and generation-specific known-hosts file hash;
- Acer client-key permissions;
- a successful key-only non-interactive connection test;
- a successful interactive terminal test;
- the session transcript location and digest; and
- confirmation that the target disk write counters did not change because of
  networking or remote login.

## Failure policy

If the wired link, SSH service, key authentication, terminal, or transcript
capture is unavailable, stop at the current non-destructive gate. Repair and
rebuild the signed generation rather than asking the operator to manually type a
large destructive sequence at the A720 console.

Network assistance is a human-error control. It must remain available without
turning the installer into a generally reachable network service.
