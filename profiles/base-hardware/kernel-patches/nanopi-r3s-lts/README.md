# NanoPi R3S LTS device tree

Linux 6.18 ships `rk3566-nanopi-r3s.dts` but not the LTS variant that Armbian
selects (`BOOT_FDT_FILE=rockchip/rk3566-nanopi-r3s-lts.dtb`). The patch adds
Armbian's `rk3566-nanopi-r3s-lts.dts` unchanged (it includes the upstream R3S
tree and enables HDMI) and registers it in the rockchip DTB Makefile.

Armbian's `board-nanopi-r3s-fix-leds.patch` (LED triggers, GMAC reset/phy-mode)
is deliberately not carried: the upstream GMAC description is kept.

`0002` drops `sd-uhs-sdr50` from `&sdmmc0`. Linux otherwise switches the SD
card to 1.8 V UHS-I signalling; a warm `reboot` does not power-cycle the card,
so FriendlyElec's eMMC SPL fails "Card did not respond to voltage select" on
the SD card and boots the factory eMMC system. `no-1-8-v` would not help: only
sdhci parses it, and sdmmc0 is dw_mmc. Cost: SD high speed (~25 MB/s) instead
of SDR50.
