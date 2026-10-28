#!/bin/vbash
# Configure wired DHCP WAN and SSH in VyOS. Boards whose network profile
# names a LAN bus also get a basic routed LAN (DHCP server, DNS forwarding,
# NAT). No AP, firewall, or modem configuration.

set -o pipefail
# Non-login SSH invocations may omit administrative program directories.
export PATH="${PATH}:/usr/sbin:/sbin"

# Optional board roles: WAN_BUS/LAN_BUS (platform, pci, usb) and LAN_ADDRESS.
BOARD_NETWORK="/usr/share/vyos-arm64-board-builder/board-network.env"
if [ -r "$BOARD_NETWORK" ]; then
    . "$BOARD_NETWORK"
fi

AUTO_SETUP=no
WIRED_IF="${WIRED_IF:-auto}"
WAN_BUS="${WAN_BUS:-}"
LAN_IF="${LAN_IF:-auto}"
LAN_BUS="${LAN_BUS:-}"
# Avoid 192.168.0.0/24 and 192.168.1.0/24, common on ISP boxes upstream.
LAN_ADDRESS="${LAN_ADDRESS:-192.168.10.1/24}"
LAN_DNS_1="${LAN_DNS_1:-1.1.1.1}"
LAN_DNS_2="${LAN_DNS_2:-9.9.9.9}"
LAN_NAT_RULE="${LAN_NAT_RULE:-110}"
ROUTE_DISTANCE="${ROUTE_DISTANCE:-1}"
LOG="/config/dhcp-wan-ssh-setup.log"
IFACE_FILE="/config/.dhcp-wan-interface"

log() {
    printf '%s %s\n' "$(date -Is)" "dhcp-wan-ssh-setup: $*" | tee -a "$LOG"
}

fail() {
    log "ERROR: $*"
    builtin exit 1
}

# VyOS configuration scripts must run with the vyattacfg primary group.
# Re-exec before argument parsing so all CLI arguments are preserved.
if [ "$(id -g -n)" != "vyattacfg" ] && [ "${VYOS_ARM64_VYATTACFG_REEXEC:-0}" != "1" ]; then
    command -v sg >/dev/null 2>&1 || fail "sg command is missing"
    SCRIPT_PATH="$(readlink -f "$0")"
    printf -v SCRIPT_Q '%q' "$SCRIPT_PATH"
    ARGS_Q=""
    for ARG in "$@"; do
        printf -v ARG_Q '%q' "$ARG"
        ARGS_Q+=" $ARG_Q"
    done
    export VYOS_ARM64_VYATTACFG_REEXEC=1
    exec sg vyattacfg -c "/bin/vbash $SCRIPT_Q$ARGS_Q"
fi

for ARG in "$@"; do
    case "$ARG" in
        --auto) AUTO_SETUP=yes ;;
        --interface=*) WIRED_IF="${ARG#*=}" ;;
        --lan-interface=*) LAN_IF="${ARG#*=}" ;;
        --lan-address=*) LAN_ADDRESS="${ARG#*=}" ;;
        --distance=*) ROUTE_DISTANCE="${ARG#*=}" ;;
        -h|--help)
            echo "dhcp-wan-ssh-setup.sh [--auto] [--interface=eth0] [--lan-interface=eth1] [--lan-address=192.168.10.1/24] [--distance=1]"
            builtin exit 0
            ;;
        *) fail "Unbekannter Parameter: $ARG" ;;
    esac
done

iface_bus() {
    basename "$(readlink -f "/sys/class/net/$1/device/subsystem" 2>/dev/null)"
}

# Without a bus, take the first wired interface (kernel probe order).
detect_wired_interface() {
    local BUS="${1:-}" CANDIDATE

    for CANDIDATE in /sys/class/net/eth* /sys/class/net/en*; do
        [ -e "$CANDIDATE" ] || continue
        CANDIDATE="${CANDIDATE##*/}"
        [ -e "/sys/class/net/$CANDIDATE/device" ] || continue
        [ -r "/sys/class/net/$CANDIDATE/address" ] || continue
        [ -z "$BUS" ] || [ "$(iface_bus "$CANDIDATE")" = "$BUS" ] || continue
        printf '%s\n' "$CANDIDATE"
        return 0
    done

    return 1
}

read_mac() {
    tr '[:upper:]' '[:lower:]' < "/sys/class/net/$1/address" 2>/dev/null
}

if [ "$WIRED_IF" = "auto" ]; then
    WIRED_IF="$(detect_wired_interface "$WAN_BUS" || true)"
fi

[ -n "$WIRED_IF" ] || fail "No wired Ethernet interface detected${WAN_BUS:+ on bus $WAN_BUS}"
[ -e "/sys/class/net/$WIRED_IF" ] || fail "Interface $WIRED_IF does not exist"

MAC="$(read_mac "$WIRED_IF")"
printf '%s\n' "$MAC" | grep -Eq '^([0-9a-f]{2}:){5}[0-9a-f]{2}$' ||
    fail "Invalide MAC-Adresse fuer $WIRED_IF: ${MAC:-leer}"

# A LAN is configured only when the board profile names its bus or the
# administrator passes --lan-interface.
if [ "$LAN_IF" = "auto" ]; then
    LAN_IF=""
    [ -z "$LAN_BUS" ] || LAN_IF="$(detect_wired_interface "$LAN_BUS" || true)"
fi
if [ -n "$LAN_IF" ]; then
    [ "$LAN_IF" != "$WIRED_IF" ] || fail "LAN and WAN must be different interfaces: $LAN_IF"
    [ -e "/sys/class/net/$LAN_IF" ] || fail "Interface $LAN_IF does not exist"

    # Only /24 LANs are supported: the DHCP pool is .100-.199 of the prefix.
    printf '%s\n' "$LAN_ADDRESS" | grep -Eq '^([0-9]{1,3}\.){3}[0-9]{1,3}/24$' ||
        fail "Invalid LAN address (expected a.b.c.d/24): $LAN_ADDRESS"
    LAN_GATEWAY="${LAN_ADDRESS%/*}"
    LAN_PREFIX="${LAN_GATEWAY%.*}"
    LAN_NET="${LAN_PREFIX}.0/24"
elif [ -n "$LAN_BUS" ]; then
    log "No LAN interface detected on bus $LAN_BUS; only WAN will be configured"
fi

case "$ROUTE_DISTANCE" in
    ''|*[!0-9]*) fail "Invalide Routendistanz: $ROUTE_DISTANCE" ;;
esac

printf '%s\n' "$WIRED_IF" > "$IFACE_FILE"
chmod 600 "$IFACE_FILE"

log "Detected: interface=$WIRED_IF MAC=$MAC LAN=${LAN_IF:-none}${LAN_IF:+ address=$LAN_ADDRESS} DHCP route distance=$ROUTE_DISTANCE"

sudo /sbin/ip link set "$WIRED_IF" up 2>/dev/null || true

[ -r /opt/vyatta/etc/functions/script-template ] ||
    fail "VyOS script-template is missing"

source /opt/vyatta/etc/functions/script-template
source "$(dirname "$(readlink -f "$0")")/setup-transaction.sh"
configure || { echo "ERROR: Cannot enter configuration mode." >&2; builtin exit 1; }
setup_session_guard

if [ -n "$LAN_IF" ]; then
    setup_set interfaces ethernet "$WIRED_IF" description 'WAN-DHCP'
else
    setup_set interfaces ethernet "$WIRED_IF" description 'WAN-LAN-DHCP'
fi
setup_set interfaces ethernet "$WIRED_IF" address 'dhcp'
setup_set interfaces ethernet "$WIRED_IF" dhcp-options default-route-distance "$ROUTE_DISTANCE"

if [ -n "$LAN_IF" ]; then
    setup_set interfaces ethernet "$LAN_IF" description 'LAN'
    setup_set interfaces ethernet "$LAN_IF" address "$LAN_ADDRESS"

    setup_set service dhcp-server shared-network-name LAN authoritative
    setup_set service dhcp-server shared-network-name LAN subnet "$LAN_NET" subnet-id '10'
    setup_set service dhcp-server shared-network-name LAN subnet "$LAN_NET" option default-router "$LAN_GATEWAY"
    setup_set service dhcp-server shared-network-name LAN subnet "$LAN_NET" option name-server "$LAN_GATEWAY"
    setup_set service dhcp-server shared-network-name LAN subnet "$LAN_NET" range 0 start "${LAN_PREFIX}.100"
    setup_set service dhcp-server shared-network-name LAN subnet "$LAN_NET" range 0 stop "${LAN_PREFIX}.199"

    setup_set service dns forwarding allow-from "$LAN_NET"
    setup_set service dns forwarding listen-address "$LAN_GATEWAY"
    setup_set service dns forwarding name-server "$LAN_DNS_1"
    setup_set service dns forwarding name-server "$LAN_DNS_2"

    setup_set nat source rule "$LAN_NAT_RULE" description 'LAN-to-WAN'
    setup_set nat source rule "$LAN_NAT_RULE" outbound-interface name "$WIRED_IF"
    setup_set nat source rule "$LAN_NAT_RULE" source address "$LAN_NET"
    setup_set nat source rule "$LAN_NAT_RULE" translation address 'masquerade'
fi
setup_set service ssh

# Seed only fresh installations; never overwrite an administrator's channel.
CHANNEL_FILE=/usr/share/vyos-arm64-board-builder/update-channel.json
if [[ "$AUTO_SETUP" == yes && ! -e /config/.dhcp-wan-ssh-firstboot-done && -r "$CHANNEL_FILE" ]]; then
    if ! "$API" existsActive system update-check url; then
        CHANNEL_URL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["url"])' "$CHANNEL_FILE")" || fail "Invalid image update channel"
        setup_set system update-check url "$CHANNEL_URL"
    fi
fi

if ! setup_commit_save; then
    discard 2>/dev/null || true
    fail "Could not commit and save wired WAN configuration"
fi
log "VyOS configuration saved (or already present)"

log "Konfigurationsphase abgeschlossen"
