#!/bin/bash
# fix-yt6801.sh — Patch Motorcomm YT6801 driver (tuxedo-yt6801) for Linux kernel 6.17+
# Fixes: from_timer, init_timer_key, del_timer_sync removed in kernel 6.17
# Author: domOpen (domopen.com)
# License: MIT

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Motorcomm YT6801 Kernel 6.17+ Fix ===${NC}"
echo ""

# Find driver source
SRC=$(find /usr/src/ -name "fuxi-gmac-phy.c" 2>/dev/null | head -1)

if [ -z "$SRC" ]; then
    echo -e "${RED}[ERROR] tuxedo-yt6801 driver source not found in /usr/src/${NC}"
    echo "Install the driver first:"
    echo "  sudo apt install -y dkms build-essential linux-headers-\$(uname -r)"
    echo "  wget https://deb.tuxedocomputers.com/ubuntu/pool/main/t/tuxedo-yt6801/tuxedo-yt6801_1.0.29tux0_all.deb"
    echo "  sudo dpkg -i tuxedo-yt6801_1.0.29tux0_all.deb"
    echo "(the install will fail on kernel 6.17+, that's expected — then run this script)"
    exit 1
fi

DRIVER_DIR=$(dirname "$SRC")
echo -e "Driver source found: ${YELLOW}${SRC}${NC}"

# Check if already patched
if grep -q "KERNEL_VERSION(6,17,0)" "$SRC"; then
    echo -e "${YELLOW}[SKIP] Driver already patched for kernel 6.17+${NC}"
    exit 0
fi

# Check kernel version
KVER=$(uname -r | cut -d. -f1-2)
echo -e "Running kernel: ${YELLOW}$(uname -r)${NC}"

# Backup
echo "[1/4] Backing up original source..."
sudo cp "$SRC" "${SRC}.bak"

# Patch
echo "[2/4] Patching fuxi-gmac-phy.c..."
sudo python3 << PATCHEOF
f = "$SRC"
with open(f, "r") as fh:
    c = fh.read()

# Fix 1: from_timer -> container_of (kernel 6.17 removed from_timer)
c = c.replace(
    "#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4,15,0))\n    struct fxgmac_pdata *pdata = from_timer(pdata, t, expansion.phy_poll_tm);\n#else",
    "#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6,17,0))\n    struct fxgmac_pdata *pdata = container_of(t, struct fxgmac_pdata, expansion.phy_poll_tm);\n#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4,15,0))\n    struct fxgmac_pdata *pdata = from_timer(pdata, t, expansion.phy_poll_tm);\n#else"
)

# Fix 2: init_timer_key -> timer_setup (kernel 6.17 removed init_timer_key)
c = c.replace(
    '''#if (LINUX_VERSION_CODE >= KERNEL_VERSION(4,15,0))
    init_timer_key(&pdata->expansion.phy_poll_tm, NULL, 0, "fuxi_phy_link_update_timer", NULL);
#else
    init_timer_key(&pdata->expansion.phy_poll_tm, 0, "fuxi_phy_link_update_timer", NULL);
#endif
    pdata->expansion.phy_poll_tm.expires = jiffies + HZ / 2;
    pdata->expansion.phy_poll_tm.function = (void *)(fxgmac_phy_link_poll);
#if (LINUX_VERSION_CODE < KERNEL_VERSION(4,15,0))
    pdata->expansion.phy_poll_tm.data = (unsigned long)pdata;
#endif
    add_timer(&pdata->expansion.phy_poll_tm);''',
    '''#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6,17,0))
    timer_setup(&pdata->expansion.phy_poll_tm, fxgmac_phy_link_poll, 0);
    pdata->expansion.phy_poll_tm.expires = jiffies + HZ / 2;
    add_timer(&pdata->expansion.phy_poll_tm);
#elif (LINUX_VERSION_CODE >= KERNEL_VERSION(4,15,0))
    init_timer_key(&pdata->expansion.phy_poll_tm, NULL, 0, "fuxi_phy_link_update_timer", NULL);
    pdata->expansion.phy_poll_tm.expires = jiffies + HZ / 2;
    pdata->expansion.phy_poll_tm.function = (void *)(fxgmac_phy_link_poll);
    add_timer(&pdata->expansion.phy_poll_tm);
#else
    init_timer_key(&pdata->expansion.phy_poll_tm, 0, "fuxi_phy_link_update_timer", NULL);
    pdata->expansion.phy_poll_tm.expires = jiffies + HZ / 2;
    pdata->expansion.phy_poll_tm.function = (void *)(fxgmac_phy_link_poll);
    pdata->expansion.phy_poll_tm.data = (unsigned long)pdata;
    add_timer(&pdata->expansion.phy_poll_tm);
#endif'''
)

# Fix 3: del_timer_sync -> timer_delete_sync (kernel 6.17 removed del_timer_sync)
c = c.replace(
    "    del_timer_sync(&pdata->expansion.phy_poll_tm);",
    '''#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6,17,0))
    timer_delete_sync(&pdata->expansion.phy_poll_tm);
#else
    del_timer_sync(&pdata->expansion.phy_poll_tm);
#endif'''
)

with open(f, "w") as fh:
    fh.write(c)
print("Patch applied successfully!")
PATCHEOF

# Detect DKMS module version
DKMS_VER=$(dkms status | grep tuxedo-yt6801 | head -1 | awk -F',' '{print $1}' | awk -F'/' '{print $2}' | tr -d ' ')
if [ -z "$DKMS_VER" ]; then
    DKMS_VER="1.0.29tux0"
fi

# Build
echo "[3/4] Building driver with DKMS..."
sudo dkms build "tuxedo-yt6801/${DKMS_VER}" -k "$(uname -r)"

# Install
echo "[4/4] Installing driver..."
sudo dkms install "tuxedo-yt6801/${DKMS_VER}" -k "$(uname -r)"

echo ""
echo -e "${GREEN}=== Done! ===${NC}"
echo ""
echo "Load the driver now:"
echo "  sudo modprobe yt6801"
echo "  ip link show"
echo ""
echo "Your Motorcomm YT6801 interface should appear (typically as enp1s0)."
echo "Bring it up with:"
echo "  sudo ip link set enp1s0 up"
echo ""
echo -e "${YELLOW}Note: This patch survives kernel updates via DKMS.${NC}"
echo -e "${YELLOW}If you upgrade to a new kernel and the build fails again,${NC}"
echo -e "${YELLOW}re-run this script.${NC}"
