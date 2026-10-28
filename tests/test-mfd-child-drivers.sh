#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL="${KERNEL:-$ROOT/cache/linux-vyos/linux-6.18.44}"
TMP="$ROOT/work/test-mfd-child-drivers"

[[ -d "$KERNEL" ]] || {
    echo "FAIL: kernel source missing: $KERNEL"
    exit 1
}

rm -rf "$TMP"
mkdir -p "$TMP"

#
# Minimal synthetic DT-driver map:
#
# The production resolver receives the same source path from the
# DT-compatible mapper. RK806 is intentionally used here as a
# regression fixture for the real hardware failure we reproduced.
#
cat > "$TMP/driver-map.tsv" <<'EOF'
rockchip,rk806	CONFIG_MFD_RK8XX_SPI	drivers/mfd/rk8xx-spi.c
EOF

"$ROOT/tools/mfd-child-drivers.py" \
    --kernel "$KERNEL" \
    --driver-map "$TMP/driver-map.tsv" \
    --output "$TMP/mfd-map.tsv"

for symbol in \
    CONFIG_PINCTRL_RK805 \
    CONFIG_INPUT_RK805_PWRKEY \
    CONFIG_REGULATOR_RK808
do
    if ! awk -F '\t' -v wanted="$symbol" \
        '$2 == wanted { found=1 } END { exit !found }' \
        "$TMP/mfd-map.tsv"
    then
        echo "FAIL: missing $symbol"
        cat "$TMP/mfd-map.tsv"
        exit 1
    fi

    echo "PASS: $symbol"
done

if ! awk -F '\t' \
    '$4 == "RK806_ID" { found=1 } END { exit !found }' \
    "$TMP/mfd-map.tsv"
then
    echo "FAIL: RK806 variant path was not resolved"
    exit 1
fi

echo "PASS: RK806_ID variant selected"

if grep -qi 'rk817' "$TMP/mfd-map.tsv"; then
    echo "FAIL: unrelated RK817 child leaked into RK806 result"
    cat "$TMP/mfd-map.tsv"
    exit 1
fi

echo "PASS: no unrelated RK817 children"

if [[ -s "$TMP/mfd-map.tsv.unresolved" ]]; then
    echo "FAIL: unresolved MFD children:"
    cat "$TMP/mfd-map.tsv.unresolved"
    exit 1
fi

echo "PASS: no unresolved MFD children"

#
# I2C RK809 (NanoPi R3S LTS): the variant comes from the compatible's
# of_device_id data and shares a stacked case label with RK817.
#
cat > "$TMP/driver-map-i2c.tsv" <<'EOF'
rockchip,rk809	CONFIG_MFD_RK8XX_I2C	drivers/mfd/rk8xx-i2c.c
EOF

"$ROOT/tools/mfd-child-drivers.py" \
    --kernel "$KERNEL" \
    --driver-map "$TMP/driver-map-i2c.tsv" \
    --output "$TMP/mfd-map-i2c.tsv"

if ! awk -F '\t' \
    '$2 == "CONFIG_REGULATOR_RK808" && $4 == "RK809_ID" { found=1 } END { exit !found }' \
    "$TMP/mfd-map-i2c.tsv"
then
    echo "FAIL: RK809 regulator child was not resolved"
    cat "$TMP/mfd-map-i2c.tsv"
    exit 1
fi

echo "PASS: RK809_ID regulator child selected"

if grep -q 'PINCTRL_RK805' "$TMP/mfd-map-i2c.tsv"; then
    echo "FAIL: RK805/RK806-only child leaked into RK809 result"
    cat "$TMP/mfd-map-i2c.tsv"
    exit 1
fi

echo "PASS: no unrelated RK806 children"

echo
echo "All MFD child-driver tests passed."
