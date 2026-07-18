#!/usr/bin/env python3
import time
import sys
import threading
from pynq import Overlay

print("[BOOT.PY] Initializing dual-register polling service...")

try:
    ol = Overlay("/boot/zynq_zed.bit")
except Exception as e:
    print(f"[BOOT.PY] CRITICAL: Failed parsing bitstream layout: {e}")
    sys.exit(1)


# =====================================================================
# THREAD 1: POLLING DAEMON FOR AXI_GPIO_0 (Switches to LEDs)
# =====================================================================
def gpio_0_daemon():
    if not hasattr(ol, "axi_gpio_0"):
        print("[Daemon 0] ERROR: 'axi_gpio_0' not found.")
        return

    gpio_0 = ol.axi_gpio_0

    # Local Hardware Register Configurations from HWH metadata:
    gpio_0.write(0x4, 0x00)  # CH1 (GPIO_TRI)  = Output (LEDs)
    gpio_0.write(0xC, 0xFF)  # CH2 (GPIO2_TRI) = Input (Switches)

    print("[Daemon 0] Polling Active. Watching Switch transitions (In0)...")

    last_state = None
    while True:
        try:
            # Read Channel 2 Data Register directly (GPIO2_DATA at offset 0x8)
            current_state = gpio_0.read(0x8)

            if current_state != last_state:
                # Write data straight to Channel 1 Data Register (GPIO_DATA at offset 0x0)
                gpio_0.write(0x0, current_state)
                last_state = current_state

            # Sleep 10ms to keep ARM CPU utilization near 0%
            time.sleep(0.01)
        except Exception as e:
            print(f"[Daemon 0] Polling exception tracking: {e}")
            time.sleep(1)


# =====================================================================
# THREAD 2: POLLING DAEMON FOR AXI_GPIO_1 (Buttons)
# =====================================================================
def gpio_1_daemon():
    if not hasattr(ol, "axi_gpio_1"):
        print("[Daemon 1] ERROR: 'axi_gpio_1' not found.")
        return

    gpio_1 = ol.axi_gpio_1
    gpio_1.write(0x4, 0xFF)  # CH1 (GPIO_TRI) = Input (Buttons)

    print("[Daemon 1] Polling Active. Watching Button transitions (In1)...")

    last_state = None
    while True:
        try:
            # Read Channel 1 Data Register directly (GPIO_DATA at offset 0x0)
            current_state = gpio_1.read(0x0)

            if current_state != last_state:
                print(
                    f"[Daemon 1] Edge transition detected! Current State: {current_state}"
                )
                last_state = current_state

            time.sleep(0.01)
        except Exception as e:
            print(f"[Daemon 1] Polling exception tracking: {e}")
            time.sleep(1)


# =====================================================================
# BACKGROUND SERVICE THREAD DEPLOYMENT
# =====================================================================
# Using daemon=False ensures these loops continue running as persistent services
t0 = threading.Thread(target=gpio_0_daemon, daemon=False)
t1 = threading.Thread(target=gpio_1_daemon, daemon=False)

t0.start()
t1.start()

print("[BOOT.PY] Register polling layers initialized successfully.")
