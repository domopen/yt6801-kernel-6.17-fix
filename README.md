# Motorcomm YT6801 — Linux Kernel 6.17+ Fix

## The Problem

The **Motorcomm YT6801** Gigabit Ethernet controller (found in Geekom Air12, various N95/N100 mini-PCs, and some laptops) has no mainline Linux kernel driver. The community relies on out-of-tree drivers like [tuxedo-yt6801](https://deb.tuxedocomputers.com/) or [dante1613/Motorcomm-YT6801](https://github.com/dante1613/Motorcomm-YT6801).

Starting with **Linux kernel 6.17**, these drivers fail to compile with the following errors:

```
fuxi-gmac-phy.c: error: implicit declaration of function 'from_timer'
fuxi-gmac-phy.c: error: implicit declaration of function 'init_timer_key'
fuxi-gmac-phy.c: error: implicit declaration of function 'del_timer_sync'
```

This happens because kernel 6.17 removed legacy timer API functions:
- `from_timer()` → use `container_of()`
- `init_timer_key()` → use `timer_setup()`
- `del_timer_sync()` → use `timer_delete_sync()`

Motorcomm [submitted patches](https://lwn.net/Articles/1016815/) for mainline inclusion (v4 as of late 2025), but then **suspended the upstreaming effort**. So here we are.

## Affected Hardware

Any device using the Motorcomm YT6801 Gigabit Ethernet controller, including but not limited to:
- **Geekom Air12 / Air12 Lite**
- **SOYO N95/N100 mini-PCs**
- Various laptops with YT6801 (Tongfang, Skikk, etc.)

Check with: `lspci | grep -i motorcomm` or `lspci | grep -i YT6801`

## Affected Distros

Any Linux distribution running **kernel 6.17+** with the `tuxedo-yt6801` DKMS driver:
- Ubuntu 24.04+ (HWE kernel)
- Linux Mint 22+
- Arch Linux (rolling)
- Fedora 42+
- Any distro with kernel ≥ 6.17

## The Fix

This repository provides a patch for `fuxi-gmac-phy.c` that adds proper `#if LINUX_VERSION_CODE` guards for kernel 6.17+, while maintaining backward compatibility with older kernels.

## Quick Install

### Prerequisites

Install the TUXEDO driver first (it will fail to build on kernel 6.17+ — that's expected):

```bash
sudo apt install -y dkms build-essential linux-headers-$(uname -r)
wget https://deb.tuxedocomputers.com/ubuntu/pool/main/t/tuxedo-yt6801/tuxedo-yt6801_1.0.29tux0_all.deb
sudo dpkg -i tuxedo-yt6801_1.0.29tux0_all.deb
# This will fail — that's OK
```

### Apply the fix

```bash
git clone https://github.com/domopen/yt6801-kernel-6.17-fix.git
cd yt6801-kernel-6.17-fix
chmod +x fix-yt6801.sh
sudo ./fix-yt6801.sh
```

### Load the driver

```bash
sudo modprobe yt6801
ip link show
# You should see your interface (typically enp1s0)
sudo ip link set enp1s0 up
```

## SecureBoot

If you have SecureBoot enabled, the module needs to be signed. The easiest options:
1. **Disable SecureBoot** in BIOS (simplest for home use)
2. **Sign the module** with MOK — see [Ubuntu's guide on DKMS and SecureBoot](https://wiki.ubuntu.com/UEFI/SecureBoot/DKMS)

## What's Changed (Technical Details)

Three functions in `fuxi-gmac-phy.c` needed updating for the kernel 6.17 timer API changes:

| Old API (< 6.17) | New API (≥ 6.17) | Purpose |
|---|---|---|
| `from_timer(pdata, t, field)` | `container_of(t, struct type, field)` | Get parent struct from timer |
| `init_timer_key(&timer, ...)` | `timer_setup(&timer, callback, flags)` | Initialize timer |
| `del_timer_sync(&timer)` | `timer_delete_sync(&timer)` | Destroy timer |

The patch adds `#if (LINUX_VERSION_CODE >= KERNEL_VERSION(6,17,0))` guards so the driver compiles on both old and new kernels.

See `fix-kernel-6.17.patch` for the raw patch.

## Will this break on future kernels?

Possibly. The `timer_setup` / `timer_delete_sync` / `container_of` APIs are the current standard and should be stable for a while. If Motorcomm ever gets their driver merged into mainline, this patch becomes unnecessary.

## Credits

- **domOpen** ([domopen.com](https://domopen.com)) — Privacy-first home automation, Bordeaux, France
- Patch developed during a late-night Suricata IDS lab session, February 14, 2026 ❤️
- Thanks to [TUXEDO Computers](https://www.tuxedocomputers.com/) for maintaining the DKMS package
- Thanks to the [dante1613](https://github.com/dante1613/Motorcomm-YT6801) and [silent-reader-cn](https://github.com/silent-reader-cn/yt6801) repos for the original driver work

## License

MIT — Do whatever you want with it. Just fix your damn ethernet.
