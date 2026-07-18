#!/usr/bin/env python3
import os
import sys
import glob
import struct
import threading
from pynq import Overlay

# =====================================================================
# Raw UIO interrupt service (one UIO per GPIO core).
#
# The device tree binds each GPIO to generic-uio:
#     &axi_gpio_0 { compatible = "generic-uio"; };  // switches, IRQ 30
#     &axi_gpio_1 { compatible = "generic-uio"; };  // buttons,  IRQ 29
# so each core gets its OWN /dev/uioN with its OWN interrupt line. We match
# each UIO to its GPIO by physical base address (names are not stable under
# generic-uio), then wait on each in a dedicated thread.
#
# Base addresses from zynq_zed.hwh:
#     axi_gpio_0 (switches->LEDs) = 0x41200000
#     axi_gpio_1 (buttons)        = 0x41210000
# =====================================================================

GPIO0_BASE = 0x41200000  # switches (CH2 in) -> LEDs (CH1 out)
GPIO1_BASE = 0x41210000  # buttons  (CH1 in)

# AXI GPIO register offsets
GPIO_DATA = 0x0
GPIO_TRI = 0x4
GPIO2_DATA = 0x8
GPIO2_TRI = 0xC
GIER = 0x11C       # Global Interrupt Enable (bit31)
IP_IER = 0x128     # IP Interrupt Enable (bit0=CH1, bit1=CH2)
IP_ISR = 0x120     # IP Interrupt Status (write-1-to-clear)

print("[BOOT.PY] Initializing per-UIO dual-GPIO interrupt service...")

try:
    ol = Overlay("/boot/zynq_zed.bit")
except Exception as e:
    print(f"[BOOT.PY] CRITICAL: Failed parsing bitstream layout: {e}")
    sys.exit(1)


def find_uio(base_addr):
    """Return /dev/uioN whose map0 physical address matches base_addr."""
    for path in sorted(glob.glob("/sys/class/uio/uio*")):
        try:
            with open(os.path.join(path, "maps/map0/addr")) as f:
                addr = int(f.read().strip(), 16)
        except (OSError, ValueError):
            continue
        if addr == base_addr:
            return "/dev/" + os.path.basename(path)
    return None


def unmask(fd):
    # uio_pdrv_genirq masks the IRQ after each fire; write uint32(1) to re-arm.
    os.write(fd, struct.pack("<I", 1))


# =====================================================================
# THREAD 1: AXI_GPIO_0 -- mirror switches (CH2 in) onto LEDs (CH1 out)
# =====================================================================
def gpio_0_daemon(dev):
    gpio_0 = ol.axi_gpio_0
    gpio_0.write(GPIO_TRI, 0x00)    # CH1 = output (LEDs)
    gpio_0.write(GPIO2_TRI, 0xFF)   # CH2 = input  (switches)
    gpio_0.write(IP_IER, 0x02)      # enable CH2 interrupt
    gpio_0.write(GIER, 0x80000000)
    gpio_0.write(GPIO_DATA, gpio_0.read(GPIO2_DATA))  # prime LEDs

    fd = os.open(dev, os.O_RDWR)
    unmask(fd)
    print(f"[Daemon 0] Armed on {dev}. Waiting for switch toggles...")

    while True:
        os.read(fd, 4)  # blocks until IRQ 30
        switch_state = gpio_0.read(GPIO2_DATA)
        gpio_0.write(GPIO_DATA, switch_state)
        gpio_0.write(IP_ISR, 0x02)  # clear CH2 status
        unmask(fd)


# =====================================================================
# THREAD 2: AXI_GPIO_1 -- report button edges (CH1 in)
# =====================================================================
def gpio_1_daemon(dev):
    gpio_1 = ol.axi_gpio_1
    gpio_1.write(GPIO_TRI, 0xFF)    # CH1 = input (buttons)
    gpio_1.write(IP_IER, 0x01)      # enable CH1 interrupt
    gpio_1.write(GIER, 0x80000000)

    fd = os.open(dev, os.O_RDWR)
    unmask(fd)
    print(f"[Daemon 1] Armed on {dev}. Waiting for button events...")

    while True:
        os.read(fd, 4)  # blocks until IRQ 29
        button_val = gpio_1.read(GPIO_DATA)
        print(f"[Daemon 1] Button edge detected! State: {button_val}")
        gpio_1.write(IP_ISR, 0x01)  # clear CH1 status
        unmask(fd)


# =====================================================================
# Resolve UIO devices by physical address and launch service threads.
# =====================================================================
dev0 = find_uio(GPIO0_BASE)
dev1 = find_uio(GPIO1_BASE)

if dev0 is None or dev1 is None:
    print(f"[BOOT.PY] CRITICAL: UIO lookup failed (gpio0={dev0}, gpio1={dev1}).")
    print("[BOOT.PY] Check that both GPIOs use compatible=\"generic-uio\" in the DT.")
    sys.exit(1)

print(f"[BOOT.PY] gpio_0 (0x{GPIO0_BASE:08X}) -> {dev0}")
print(f"[BOOT.PY] gpio_1 (0x{GPIO1_BASE:08X}) -> {dev1}")

t0 = threading.Thread(target=gpio_0_daemon, args=(dev0,), daemon=False)
t1 = threading.Thread(target=gpio_1_daemon, args=(dev1,), daemon=False)
t0.start()
t1.start()

print("[BOOT.PY] Both interrupt handlers running.")
