#!/bin/sh
# Replace a kernel-random NIC MAC with a stable, board-unique one before
# VyOS (65-vyos-net.rules) names interfaces by hw-id. Called from udev.
set -eu

IFACE="$1"

SERIAL="$(cat /sys/class/dmi/id/product_serial 2>/dev/null || true)"
if [ -z "$SERIAL" ]; then
    SERIAL="$(tr -d '\000' < /proc/device-tree/serial-number 2>/dev/null || true)"
fi
# Without a board serial, keep the kernel address rather than invent one.
[ -n "$SERIAL" ] || exit 0

DEVICE="$(basename "$(readlink -f "/sys/class/net/$IFACE/device")")"
HASH="$(printf 'vyos-arm64-mac:%s:%s' "$SERIAL" "$DEVICE" | /usr/bin/sha256sum | cut -c1-12)"
# Locally administered, unicast.
FIRST="$(printf '%02x' $(( (0x$(printf '%s' "$HASH" | cut -c1-2) & 0xfc) | 0x02 )))"
MAC="$FIRST$(printf '%s' "$HASH" | cut -c3-12 | sed 's/../:&/g')"

/sbin/ip link set dev "$IFACE" address "$MAC"
