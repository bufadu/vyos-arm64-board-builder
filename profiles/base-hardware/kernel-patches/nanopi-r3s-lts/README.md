# NanoPi R3S LTS device tree

Linux 6.18 ships `rk3566-nanopi-r3s.dts` but not the LTS variant that Armbian
selects (`BOOT_FDT_FILE=rockchip/rk3566-nanopi-r3s-lts.dtb`). The patch adds
Armbian's `rk3566-nanopi-r3s-lts.dts` unchanged (it includes the upstream R3S
tree and enables HDMI) and registers it in the rockchip DTB Makefile.

Armbian's `board-nanopi-r3s-fix-leds.patch` (LED triggers, GMAC reset/phy-mode)
is deliberately not carried: the upstream GMAC description is kept.
