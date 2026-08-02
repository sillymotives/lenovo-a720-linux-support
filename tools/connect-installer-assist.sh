#!/bin/sh
# SPDX-License-Identifier: MIT
#
# Open the generation-pinned SSH assistance channel to a signed A720 rescue or
# installer environment. This helper never disables host-key checking and never
# falls back to password authentication.

export LC_ALL=C
umask 077

PROG=${0##*/}

usage()
{
    cat <<USAGE
Usage:
  $PROG --host ADDRESS --identity PRIVATE_KEY --generation ID
      [--user USER] [--port PORT] [--known-hosts-directory DIRECTORY]
      [-- REMOTE_COMMAND [ARGUMENT ...]]

The first connection pins the target host key into a generation-specific file.
A changed key for the same generation is rejected by SSH.
USAGE
}

fail()
{
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

have()
{
    command -v "$1" >/dev/null 2>&1
}

value_required()
{
    [ "$#" -ge 2 ] || fail "$1 requires a value"
}

HOST=''
IDENTITY=''
GENERATION=''
REMOTE_USER='root'
PORT='22'
KNOWN_HOSTS_DIRECTORY=${XDG_STATE_HOME:-${HOME:-}/.local/state}/darkstar-installer

while [ "$#" -gt 0 ]; do
    case "$1" in
        --host)
            value_required "$@"
            HOST=$2
            shift 2
            ;;
        --identity)
            value_required "$@"
            IDENTITY=$2
            shift 2
            ;;
        --generation)
            value_required "$@"
            GENERATION=$2
            shift 2
            ;;
        --user)
            value_required "$@"
            REMOTE_USER=$2
            shift 2
            ;;
        --port)
            value_required "$@"
            PORT=$2
            shift 2
            ;;
        --known-hosts-directory)
            value_required "$@"
            KNOWN_HOSTS_DIRECTORY=$2
            shift 2
            ;;
        --)
            shift
            break
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            fail "unknown argument: $1"
            ;;
    esac
done

have ssh || fail 'ssh is not installed on the Acer.'
have stat || fail 'stat is required to verify private-key permissions.'
have mkdir || fail 'mkdir is required.'

[ -n "$HOST" ] || fail '--host is required.'
[ -n "$IDENTITY" ] || fail '--identity is required.'
[ -n "$GENERATION" ] || fail '--generation is required.'
[ -n "$REMOTE_USER" ] || fail '--user must not be empty.'

case "$GENERATION" in
    *[!A-Za-z0-9._-]*|'')
        fail 'generation ID may contain only letters, digits, dot, underscore, and hyphen.'
        ;;
esac

case "$PORT" in
    *[!0-9]*|'') fail '--port must be an integer.' ;;
esac

[ "$PORT" -ge 1 ] 2>/dev/null || fail '--port must be between 1 and 65535.'
[ "$PORT" -le 65535 ] 2>/dev/null || fail '--port must be between 1 and 65535.'

[ -f "$IDENTITY" ] || fail "private key is absent: $IDENTITY"
[ ! -L "$IDENTITY" ] || fail 'private key must not be a symbolic link.'

MODE=$(stat -c '%a' "$IDENTITY" 2>/dev/null) ||
    fail 'could not inspect private-key permissions.'

case "$MODE" in
    *[!0-7]*|'') fail "unexpected private-key mode: $MODE" ;;
esac

GROUP_DIGIT=$((MODE / 10 % 10))
OTHER_DIGIT=$((MODE % 10))

[ "$GROUP_DIGIT" -eq 0 ] && [ "$OTHER_DIGIT" -eq 0 ] ||
    fail "private key permissions are too broad: mode $MODE"

mkdir -p -- "$KNOWN_HOSTS_DIRECTORY" ||
    fail "could not create known-hosts directory: $KNOWN_HOSTS_DIRECTORY"

chmod 700 -- "$KNOWN_HOSTS_DIRECTORY" ||
    fail 'could not restrict known-hosts directory permissions.'

KNOWN_HOSTS="$KNOWN_HOSTS_DIRECTORY/known_hosts.$GENERATION"
touch -- "$KNOWN_HOSTS" || fail "could not create known-hosts file: $KNOWN_HOSTS"
chmod 600 -- "$KNOWN_HOSTS" || fail 'could not restrict known-hosts permissions.'

printf 'A720 installer assistance\n'
printf 'Generation:       %s\n' "$GENERATION"
printf 'Remote endpoint:  %s@%s:%s\n' "$REMOTE_USER" "$HOST" "$PORT"
printf 'Known-hosts file: %s\n' "$KNOWN_HOSTS"
printf '%s\n' 'Authentication:   public key only'
printf '%s\n' 'Forwarding:       disabled'
printf '\n'

if [ "$#" -gt 0 ]; then
    exec ssh \
        -p "$PORT" \
        -l "$REMOTE_USER" \
        -i "$IDENTITY" \
        -o BatchMode=yes \
        -o CheckHostIP=yes \
        -o ClearAllForwardings=yes \
        -o ExitOnForwardFailure=yes \
        -o ForwardAgent=no \
        -o ForwardX11=no \
        -o IdentitiesOnly=yes \
        -o KbdInteractiveAuthentication=no \
        -o PasswordAuthentication=no \
        -o PreferredAuthentications=publickey \
        -o RequestTTY=force \
        -o ServerAliveCountMax=3 \
        -o ServerAliveInterval=15 \
        -o StrictHostKeyChecking=accept-new \
        -o Tunnel=no \
        -o UpdateHostKeys=no \
        -o UserKnownHostsFile="$KNOWN_HOSTS" \
        -o VerifyHostKeyDNS=no \
        -- "$HOST" "$@"
fi

exec ssh \
    -p "$PORT" \
    -l "$REMOTE_USER" \
    -i "$IDENTITY" \
    -o BatchMode=yes \
    -o CheckHostIP=yes \
    -o ClearAllForwardings=yes \
    -o ExitOnForwardFailure=yes \
    -o ForwardAgent=no \
    -o ForwardX11=no \
    -o IdentitiesOnly=yes \
    -o KbdInteractiveAuthentication=no \
    -o PasswordAuthentication=no \
    -o PreferredAuthentications=publickey \
    -o RequestTTY=force \
    -o ServerAliveCountMax=3 \
    -o ServerAliveInterval=15 \
    -o StrictHostKeyChecking=accept-new \
    -o Tunnel=no \
    -o UpdateHostKeys=no \
    -o UserKnownHostsFile="$KNOWN_HOSTS" \
    -o VerifyHostKeyDNS=no \
    -- "$HOST"
