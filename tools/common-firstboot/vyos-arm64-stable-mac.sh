#!/bin/sh
# Replace a kernel-random NIC MAC with a stable, board-unique one before
# VyOS (65-vyos-net.rules) names interfaces by hw-id. Called from udev.
# A non-zero exit leaves the NIC to systemd's default MAC policy.
set -eu

IFACE="$1"

# Boot with vyos_arm64.stable_mac=0 to keep the kernel/systemd address.
case " $(cat /proc/cmdline) " in
    *" vyos_arm64.stable_mac=0 "*) exit 1 ;;
esac

SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
if [ -z "$SERIAL" ]; then
    SERIAL="$(tr -d '\000' < /proc/device-tree/serial-number 2>/dev/null || true)"
fi
[ -n "$SERIAL" ] || exit 1

DEVICE="$(basename "$(readlink -f "/sys/class/net/$IFACE/device")")"
HASH="$(printf 'vyos-arm64-mac:%s:%s' "$SERIAL" "$DEVICE" | /usr/bin/sha256sum | cut -c1-12)"
# Locally administered, unicast.
FIRST="$(printf '%02x' $(( (0x$(printf '%s' "$HASH" | cut -c1-2) & 0xfc) | 0x02 )))"
MAC="$FIRST$(printf '%s' "$HASH" | cut -c3-12 | sed 's/../:&/g')"

/sbin/ip link set dev "$IFACE" address "$MAC"
