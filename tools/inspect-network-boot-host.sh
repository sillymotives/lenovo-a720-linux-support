#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Read-only inventory for a Linux machine before it becomes a network-boot host.
# The script changes no settings, starts no services, and omits hardware
# addresses. Its output can still contain private hostnames and IP addresses;
# keep generated reports out of the public repository.

set -eu
export LC_ALL=C

PXE_SERVICE=${PXE_SERVICE:-}
PXE_GENERATION_ROOT=${PXE_GENERATION_ROOT:-}
PXE_LEASE_FILE=${PXE_LEASE_FILE:-}
EXPECTED_PXE_CLIENTS=${EXPECTED_PXE_CLIENTS:-1}

section()
{
    printf '\n=== %s ===\n' "$1"
}

have()
{
    command -v "$1" >/dev/null 2>&1
}

show_command()
{
    label=$1
    shift

    printf '%s\n' "--- $label ---"
    "$@" 2>&1 || printf '[command unavailable or returned non-zero]\n'
}

section 'Identity and operating system'
printf 'timestamp=%s\n' "$(date --iso-8601=seconds 2>/dev/null || date)"
printf 'hostname=%s\n' "$(hostname)"
printf 'architecture=%s\n' "$(uname -m)"
printf 'kernel=%s\n' "$(uname -r)"

if [ -r /etc/os-release ]; then
    sed -n 's/^PRETTY_NAME=//p' /etc/os-release
fi

if [ -d /sys/firmware/efi ]; then
    echo 'firmware_boot=UEFI'
else
    echo 'firmware_boot=legacy-BIOS'
fi

section 'Storage available for installer assets'
df -hT / /home 2>/dev/null | awk 'NR == 1 || !seen[$7]++'

section 'Network devices without hardware addresses'
for path in /sys/class/net/*; do
    [ -e "$path" ] || continue
    device=${path##*/}
    [ "$device" = lo ] && continue

    printf '%s: ' "$device"
    printf 'operstate=%s ' "$(cat "$path/operstate" 2>/dev/null || echo unknown)"
    printf 'carrier=%s ' "$(cat "$path/carrier" 2>/dev/null || echo unknown)"
    printf 'type=%s\n' "$(cat "$path/type" 2>/dev/null || echo unknown)"
done

if have ip; then
    section 'IPv4 addresses and routes'
    show_command 'global IPv4 addresses' ip -4 -brief address show scope global
    show_command 'IPv4 routes' ip -4 route show

    section 'IPv6 routes'
    show_command 'IPv6 default and connected routes' ip -6 route show
fi

if have nmcli; then
    section 'NetworkManager state'
    show_command 'general state' nmcli general status
    show_command 'active connections' \
        nmcli -f NAME,TYPE,DEVICE,STATE connection show --active
    show_command 'device state' \
        nmcli -f DEVICE,TYPE,STATE,CONNECTION device status

    section 'DHCP information'
    for device in $(
        nmcli -t -f DEVICE,STATE device status 2>/dev/null |
        awk -F: '$2 == "connected" { print $1 }'
    ); do
        [ "$device" = lo ] && continue
        printf '%s\n' "--- $device ---"
        nmcli -g IP4.DHCP4.OPTION device show "$device" 2>/dev/null |
            grep -E \
                '^(dhcp_server_identifier|routers|subnet_mask|domain_name_servers|domain_name) = ' ||
            echo '[no IPv4 DHCP options reported]'
    done
fi

section 'Listening network ports'
if have ss; then
    ss -lntu 2>/dev/null |
        awk 'NR == 1 || $5 ~ /:(53|67|68|69|80|443|4011)$/'
else
    echo 'ss is unavailable.'
fi

section 'Potentially conflicting services'
for unit in \
    dnsmasq.service \
    tftpd-hpa.service \
    isc-dhcp-server.service \
    kea-dhcp4-server.service \
    nginx.service \
    apache2.service \
    systemd-networkd.service \
    systemd-resolved.service \
    NetworkManager.service
do
    if have systemctl; then
        printf '%-30s %s\n' \
            "$unit" "$(systemctl is-active "$unit" 2>/dev/null || true)"
    fi
done

section 'Selected PXE service hardening'
if [ -n "$PXE_SERVICE" ] && have systemctl; then
    printf 'service=%s\n' "$PXE_SERVICE"
    systemctl show "$PXE_SERVICE" \
        -p FragmentPath \
        -p DropInPaths \
        -p User \
        -p Group \
        -p DynamicUser \
        -p UMask \
        -p NoNewPrivileges \
        -p PrivateTmp \
        -p ProtectSystem \
        -p ProtectHome \
        -p ProtectKernelTunables \
        -p ProtectKernelModules \
        -p ProtectControlGroups \
        -p RestrictAddressFamilies \
        -p RestrictNamespaces \
        -p LockPersonality \
        -p MemoryDenyWriteExecute \
        -p CapabilityBoundingSet \
        -p AmbientCapabilities \
        -p SystemCallArchitectures \
        -p SystemCallFilter \
        -p ReadOnlyPaths \
        -p ReadWritePaths \
        -p IPAddressDeny \
        -p IPAddressAllow 2>/dev/null ||
        echo '[selected service is unavailable]'

    fragment=$(systemctl show "$PXE_SERVICE" -p FragmentPath --value 2>/dev/null || true)
    if [ -n "$fragment" ] && [ -r "$fragment" ] && have sha256sum; then
        sha256sum "$fragment"
    fi
else
    echo 'Set PXE_SERVICE to inspect one service unit without changing it.'
fi

section 'Pinned generation permissions'
if [ -n "$PXE_GENERATION_ROOT" ] && [ -d "$PXE_GENERATION_ROOT" ]; then
    resolved_generation=$(readlink -f "$PXE_GENERATION_ROOT" 2>/dev/null || true)
    printf 'generation_root=%s\n' "${resolved_generation:-unresolved}"

    if have stat; then
        stat -c 'mode=%a owner=%U:%G type=%F path=%n' "$PXE_GENERATION_ROOT" 2>/dev/null || true
    fi

    if have find; then
        writable_count=$(
            find "$PXE_GENERATION_ROOT" -xdev \
                \( -type f -o -type d \) -perm /022 -print 2>/dev/null |
            awk 'END { print NR + 0 }'
        )
        printf 'group_or_other_writable_members=%s\n' "$writable_count"
    fi

    if [ -r "$PXE_GENERATION_ROOT/SHA256SUMS" ] && have sha256sum; then
        sha256sum "$PXE_GENERATION_ROOT/SHA256SUMS"

        if (
            cd "$PXE_GENERATION_ROOT" &&
            sha256sum -c SHA256SUMS >/dev/null 2>&1
        ); then
            echo 'generation_manifest_status=verified'
        else
            echo 'generation_manifest_status=review-required'
        fi
    fi
else
    echo 'Set PXE_GENERATION_ROOT to inspect a pinned generation directory.'
fi

section 'Active PXE lease count without client identifiers'
if [ -n "$PXE_LEASE_FILE" ] && [ -r "$PXE_LEASE_FILE" ]; then
    now=$(date +%s)
    active_clients=$(
        awk -v now="$now" '$1 ~ /^[0-9]+$/ && $1 >= now { count++ } END { print count + 0 }' \
            "$PXE_LEASE_FILE"
    )
    printf 'active_lease_records=%s\n' "$active_clients"
    printf 'expected_active_clients=%s\n' "$EXPECTED_PXE_CLIENTS"

    if [ "$active_clients" -eq "$EXPECTED_PXE_CLIENTS" ] 2>/dev/null; then
        echo 'lease_count_status=expected'
    else
        echo 'lease_count_status=review-required'
    fi
else
    echo 'Set PXE_LEASE_FILE to count active leases without printing identifiers.'
fi

section 'Network-boot commands and packages'
for command_name in \
    dnsmasq in.tftpd nginx apache2 python3 ipxe pxelinux.0 grub-mknetdir
 do
    if have "$command_name"; then
        printf '%-20s %s\n' "$command_name" "$(command -v "$command_name")"
    else
        printf '%-20s %s\n' "$command_name" 'not installed'
    fi
 done

if have dpkg-query; then
    echo
    dpkg-query -W -f='${binary:Package}\t${Version}\n' \
        dnsmasq dnsmasq-base tftpd-hpa ipxe pxelinux syslinux-common \
        grub-efi-amd64-bin nginx-light nginx apache2 2>/dev/null || true
fi

section 'Firewall summary'
if have nft; then
    if [ "$(id -u)" -eq 0 ]; then
        nft list ruleset 2>/dev/null |
            grep -E '(^table |hook input|policy |dport|sport)' |
            head -n 160 || true
    else
        echo 'nft is present; run as root for a read-only ruleset summary.'
    fi
else
    echo 'nft is unavailable.'
fi

section 'Topology questions'
echo 'Record the physical cable arrangement separately:'
echo '  1. provisioning host and target through the same router or switch; or'
echo '  2. direct Ethernet cable between provisioning host and target.'
echo 'Also record whether the existing DHCP service can be configured.'
echo
echo 'No settings, services, files, firewall rules, or interfaces were changed.'
