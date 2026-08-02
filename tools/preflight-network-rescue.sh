#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-2.0-only
# Read-only proof for the A720 network-rescue environment.

set -uo pipefail
export LC_ALL=C
umask 077

PROG=${0##*/}
FAILURES=0
WARNINGS=0

usage()
{
    cat <<USAGE
Usage:
  $PROG fingerprint --target DEVICE

  $PROG rescue --target DEVICE --expected-fingerprint SHA256
      --expected-manifest-sha256 SHA256 --generation-id ID
      --generation-file PATH --manifest PATH --artifact-root DIRECTORY
      [--observe-seconds N] [--report /run/FILE.log|-]
USAGE
}

pass() { printf 'PASS: %s\n' "$*"; }
warn() { WARNINGS=$((WARNINGS + 1)); printf 'WARN: %s\n' "$*" >&2; }
fail() { FAILURES=$((FAILURES + 1)); printf 'FAIL: %s\n' "$*" >&2; }
fatal() { printf 'ERROR: %s\n' "$*" >&2; exit 2; }
section() { printf '\n=== %s ===\n' "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

is_sha256()
{
    [ "${#1}" -eq 64 ] || return 1
    case "$1" in *[!0-9A-Fa-f]*) return 1 ;; esac
}

need_commands()
{
    local command_name
    for command_name in awk blockdev cat date findmnt grep id ip lsblk \
        readlink sed sha256sum sleep swapon tee udevadm uname; do
        have "$command_name" || fatal "missing required command: $command_name"
    done
}

resolve_disk()
{
    local input=$1 disk type
    disk=$(readlink -f -- "$input" 2>/dev/null || true)
    [ -b "$disk" ] || fatal "not a block device: $input"
    type=$(lsblk -ndo TYPE -- "$disk" 2>/dev/null | sed -n '1p')
    [ "$type" = disk ] || fatal "target is not a whole disk: $disk"
    printf '%s\n' "$disk"
}

identity_material()
{
    local disk=$1 properties key value size
    properties=$(udevadm info --query=property --name "$disk" 2>/dev/null) || return 1

    for key in ID_WWN_WITH_EXTENSION ID_WWN ID_SERIAL_SHORT ID_SERIAL; do
        value=$(printf '%s\n' "$properties" | sed -n "s/^${key}=//p" | sed -n '1p')
        [ -n "$value" ] && break
    done

    [ -n "${value:-}" ] || return 1
    size=$(blockdev --getsize64 "$disk" 2>/dev/null) || return 1
    printf '%s\n%s\n%s\n' "$key" "$value" "$size"
}

fingerprint()
{
    identity_material "$1" | sha256sum | awk '{ print $1 }'
}

public_disk_info()
{
    local disk=$1
    printf 'device:           %s\n' "$disk"
    printf 'model:            %s\n' "$(lsblk -ndo MODEL -- "$disk" | sed -n '1p')"
    printf 'transport:        %s\n' "$(lsblk -ndo TRAN -- "$disk" | sed -n '1p')"
    printf 'size bytes:       %s\n' "$(blockdev --getsize64 "$disk")"
    printf 'kernel read-only: %s\n' "$(blockdev --getro "$disk")"
}

uses_target()
{
    local source=${1%%\[*} resolved
    resolved=$(readlink -f -- "$source" 2>/dev/null || true)
    [ -b "$resolved" ] || return 1
    lsblk -s -nrpo PATH -- "$resolved" 2>/dev/null | grep -Fxq -- "$TARGET"
}

setup_report()
{
    local report=$1 run_type
    [ -n "$report" ] || report="/run/darkstar-network-rescue-$(date +%Y%m%d-%H%M%S).log"

    if [ "$report" = - ]; then
        REPORT=-
        return
    fi

    case "$report" in /run/*) ;; *) fatal 'report must be under /run or exactly -' ;; esac
    run_type=$(findmnt -T /run -no FSTYPE 2>/dev/null || true)
    [ "$run_type" = tmpfs ] || fatal '/run is not tmpfs; use --report -'

    REPORT=$report
    exec > >(tee -- "$REPORT") 2>&1
}

check_artifact_storage()
{
    local source fstype options
    read -r source fstype options < <(
        findmnt -T "$ARTIFACT_ROOT" -no SOURCE,FSTYPE,OPTIONS 2>/dev/null || true
    )

    printf 'artifact source:  %s\n' "${source:-unknown}"
    printf 'artifact fstype:  %s\n' "${fstype:-unknown}"
    printf 'artifact options: %s\n' "${options:-unknown}"

    case "${source:-}" in
        /dev/*)
            if uses_target "$source"; then
                fail 'artifact storage is backed by the target disk'
            else
                pass 'artifact storage uses another block device'
            fi
            ;;
        *)
            case "${fstype:-}" in
                tmpfs|ramfs|squashfs|iso9660|erofs|nfs|nfs4|cifs|9p)
                    pass "artifact storage is independent of the target disk: $fstype"
                    ;;
                *) fail "cannot prove artifact storage is target-independent: ${fstype:-unknown}" ;;
            esac
            ;;
    esac

    case "${fstype:-}" in
        tmpfs|ramfs|squashfs|iso9660|erofs) pass 'artifact storage is immutable or memory-backed' ;;
        *) case ",${options:-}," in *,ro,*) pass 'artifact storage is mounted read-only' ;;
               *) warn 'artifact storage is writable; hashes prove content only' ;; esac ;;
    esac
}

verify_manifest()
{
    local line hash relative file canonical actual line_number=0 checked=0

    while IFS= read -r line || [ -n "$line" ]; do
        line_number=$((line_number + 1))
        case "$line" in ''|'#'*) continue ;; esac

        if [[ "$line" =~ ^([0-9A-Fa-f]{64})[[:space:]]+\*?(.+)$ ]]; then
            hash=${BASH_REMATCH[1],,}
            relative=${BASH_REMATCH[2]}
        else
            fail "invalid manifest line $line_number"
            continue
        fi

        case "$relative" in /*|..|../*|*/../*|*/..|*\\*)
            fail "unsafe manifest path on line $line_number"
            continue
            ;;
        esac

        file=$ARTIFACT_ROOT/$relative
        [ -f "$file" ] || { fail "missing artifact: $relative"; continue; }
        [ ! -L "$file" ] || { fail "artifact is a symlink: $relative"; continue; }

        canonical=$(readlink -f -- "$file" 2>/dev/null || true)
        case "$canonical" in "$ARTIFACT_ROOT"/*) ;; *)
            fail "artifact escapes root: $relative"
            continue
            ;;
        esac

        actual=$(sha256sum -- "$file" | awk '{ print $1 }')
        if [ "$actual" = "$hash" ]; then
            pass "artifact hash matches: $relative"
            checked=$((checked + 1))
        else
            fail "artifact hash mismatch: $relative"
        fi
    done < "$MANIFEST"

    [ "$checked" -gt 0 ] && pass "validated $checked artifact(s)" || fail 'no artifacts validated'
}

check_generation()
{
    local actual_generation actual_manifest

    [ -r "$GENERATION_FILE" ] || fatal "unreadable generation file: $GENERATION_FILE"
    [ -r "$MANIFEST" ] || fatal "unreadable manifest: $MANIFEST"
    [ -d "$ARTIFACT_ROOT" ] || fatal "invalid artifact root: $ARTIFACT_ROOT"

    GENERATION_FILE=$(readlink -f -- "$GENERATION_FILE")
    MANIFEST=$(readlink -f -- "$MANIFEST")
    ARTIFACT_ROOT=$(readlink -f -- "$ARTIFACT_ROOT")

    actual_generation=$(sed -n '/[^[:space:]]/ { s/[[:space:]]*$//; p; q; }' "$GENERATION_FILE")
    actual_manifest=$(sha256sum -- "$MANIFEST" | awk '{ print $1 }')

    printf 'expected generation:       %s\n' "$GENERATION_ID"
    printf 'reported generation:       %s\n' "${actual_generation:-missing}"
    printf 'expected manifest SHA-256: %s\n' "$EXPECTED_MANIFEST"
    printf 'actual manifest SHA-256:   %s\n' "$actual_manifest"

    [ "$actual_generation" = "$GENERATION_ID" ] && pass 'pinned generation matches' || fail 'generation mismatch'
    [ "$actual_manifest" = "$EXPECTED_MANIFEST" ] && pass 'pinned manifest matches' || fail 'manifest mismatch'

    check_artifact_storage
    verify_manifest
}

check_network()
{
    local path interface carrier=0
    ip -brief link show 2>/dev/null || true
    ip -4 route show 2>/dev/null || true

    for path in /sys/class/net/*; do
        [ -e "$path" ] || continue
        interface=${path##*/}
        [ "$interface" = lo ] && continue
        [ "$(cat "$path/carrier" 2>/dev/null || printf 0)" = 1 ] && carrier=1
    done

    [ "$carrier" -eq 1 ] && pass 'a non-loopback interface has carrier' || fail 'no network carrier detected'
}

check_target_unused()
{
    local source mountpoint fstype options swap start_failures=$FAILURES

    lsblk -nrpo PATH,TYPE,FSTYPE,SIZE,MOUNTPOINTS -- "$TARGET" || fail 'cannot inspect target tree'

    while read -r source mountpoint fstype options; do
        case "$source" in /dev/*)
            if uses_target "$source"; then
                fail "target-backed filesystem is mounted: $source on $mountpoint"
            fi
            ;;
        esac
    done < <(findmnt -rn -o SOURCE,TARGET,FSTYPE,OPTIONS 2>/dev/null)

    while IFS= read -r swap; do
        [ -n "$swap" ] && uses_target "$swap" && fail "target-backed swap is active: $swap"
    done < <(swapon --show=NAME --noheadings 2>/dev/null)

    [ "$FAILURES" -eq "$start_failures" ] && pass 'target disk has no mounted filesystems or active swap'
}

write_counters()
{
    awk '{ print $5, $7 }' "/sys/class/block/${TARGET##*/}/stat"
}

observe_writes()
{
    local before_w before_s after_w after_s delta_w delta_s
    read -r before_w before_s < <(write_counters) || { fail 'cannot read initial write counters'; return; }
    sleep "$OBSERVE_SECONDS"
    read -r after_w after_s < <(write_counters) || { fail 'cannot read final write counters'; return; }

    delta_w=$((after_w - before_w))
    delta_s=$((after_s - before_s))
    printf 'write operations delta: %s\n' "$delta_w"
    printf 'sectors written delta: %s\n' "$delta_s"

    [ "$delta_w" -eq 0 ] && [ "$delta_s" -eq 0 ] && \
        pass 'target recorded no writes during observation' || \
        fail 'target write counters changed during observation'
}

value_required()
{
    [ "$#" -ge 2 ] || fatal "$1 requires a value"
}

MODE=${1:-}
case "$MODE" in -h|--help|'') usage; exit 0 ;; fingerprint|rescue) shift ;; *) usage; fatal "unknown mode: $MODE" ;; esac

TARGET_INPUT=''
EXPECTED_FINGERPRINT=''
EXPECTED_MANIFEST=''
GENERATION_ID=''
GENERATION_FILE=''
MANIFEST=''
ARTIFACT_ROOT=''
OBSERVE_SECONDS=10
REPORT_INPUT=''

while [ "$#" -gt 0 ]; do
    case "$1" in
        --target) value_required "$@"; TARGET_INPUT=$2; shift 2 ;;
        --expected-fingerprint) value_required "$@"; EXPECTED_FINGERPRINT=${2,,}; shift 2 ;;
        --expected-manifest-sha256) value_required "$@"; EXPECTED_MANIFEST=${2,,}; shift 2 ;;
        --generation-id) value_required "$@"; GENERATION_ID=$2; shift 2 ;;
        --generation-file) value_required "$@"; GENERATION_FILE=$2; shift 2 ;;
        --manifest) value_required "$@"; MANIFEST=$2; shift 2 ;;
        --artifact-root) value_required "$@"; ARTIFACT_ROOT=$2; shift 2 ;;
        --observe-seconds) value_required "$@"; OBSERVE_SECONDS=$2; shift 2 ;;
        --report) value_required "$@"; REPORT_INPUT=$2; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fatal "unknown argument: $1" ;;
    esac
done

need_commands
[ -n "$TARGET_INPUT" ] || fatal '--target is required'
TARGET=$(resolve_disk "$TARGET_INPUT")
ACTUAL_FINGERPRINT=$(fingerprint "$TARGET") || fatal 'stable WWN or serial identity is unavailable'

if [ "$MODE" = fingerprint ]; then
    public_disk_info "$TARGET"
    printf 'identity SHA-256: %s\n' "$ACTUAL_FINGERPRINT"
    exit 0
fi

[ "$(id -u)" -eq 0 ] || fatal 'rescue mode must run as root'
is_sha256 "$EXPECTED_FINGERPRINT" || fatal 'invalid --expected-fingerprint'
is_sha256 "$EXPECTED_MANIFEST" || fatal 'invalid --expected-manifest-sha256'
[[ "$GENERATION_ID" =~ ^[A-Za-z0-9._-]+$ ]] || fatal 'invalid --generation-id'
[ -n "$GENERATION_FILE" ] || fatal '--generation-file is required'
[ -n "$MANIFEST" ] || fatal '--manifest is required'
[ -n "$ARTIFACT_ROOT" ] || fatal '--artifact-root is required'
[[ "$OBSERVE_SECONDS" =~ ^[0-9]+$ ]] || fatal 'observation time must be an integer'
[ "$OBSERVE_SECONDS" -ge 1 ] && [ "$OBSERVE_SECONDS" -le 300 ] || fatal 'observation time must be 1-300 seconds'

setup_report "$REPORT_INPUT"
printf 'Darkstar network-rescue preflight\nStarted: %s\nMode: READ ONLY\nReport: %s\n' \
    "$(date --iso-8601=seconds 2>/dev/null || date)" "$REPORT"

section 'Rescue environment'
uname -a
[ -d /sys/firmware/efi ] && pass 'UEFI runtime services are present' || warn 'UEFI runtime services are absent'
printf 'root source: %s\n' "$(findmnt -no SOURCE / 2>/dev/null || printf unknown)"
printf 'root fstype: %s\n' "$(findmnt -no FSTYPE / 2>/dev/null || printf unknown)"

section 'Network'
check_network

section 'Pinned generation'
check_generation

section 'Target identity'
public_disk_info "$TARGET"
printf 'expected identity SHA-256: %s\n' "$EXPECTED_FINGERPRINT"
printf 'actual identity SHA-256:   %s\n' "$ACTUAL_FINGERPRINT"
[ "$ACTUAL_FINGERPRINT" = "$EXPECTED_FINGERPRINT" ] && pass 'target identity matches' || fail 'target identity mismatch'
[ "$(blockdev --getro "$TARGET")" = 1 ] && pass 'kernel marks target read-only' || warn 'target is not kernel-enforced read-only'

section 'Target usage'
check_target_unused

section 'Write observation'
observe_writes

section 'Result'
printf 'Failures: %s\nWarnings: %s\nReport: %s\n' "$FAILURES" "$WARNINGS" "$REPORT"
printf '%s\n' 'This proves only the inspected generation, target identity, current mount/swap state, and the measured no-write interval.'

[ "$FAILURES" -eq 0 ] && { pass 'network-rescue preflight passed'; exit 0; }
printf 'STOP: do not repartition, format, restore, or install.\n' >&2
exit 1
