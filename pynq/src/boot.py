#!/usr/bin/env python3
import sys
import asyncio
from pynq import Overlay

GPIO0_BASE = 0x41200000  # Switches (CH2 in) -> LEDs (CH1 out)
GPIO1_BASE = 0x41210000  # Buttons  (CH1 in)

# AXI GPIO Register Offsets
GPIO_DATA = 0x0
GPIO_TRI = 0x4

LED_HEARTBEAT_MASK = 0x80  # Top LED (Bit 7) used for heartbeat

try:
    ol = Overlay("/home/xilinx/ycorrales/zedboard.bit")
except Exception as e:
    print(f"[BOOT.PY] CRITICAL: Failed parsing bitstream layout: {e}")
    sys.exit(1)

gpio0 = ol.axi_gpio_0


def led_apply(clear_mask: int, set_bits: int):
    """
    Merge bits into LED shadow register and push to hardware.
    """

    global led_state
    clear_mask &= 0xFF
    set_bits &= 0xFF

    inverted_mask = (~clear_mask) & 0xFF
    cleared_state = led_state & inverted_mask
    applied_bits = set_bits & clear_mask

    led_state = (cleared_state | applied_bits) & 0xFF
    gpio0.write(GPIO_DATA, led_state)


async def heartbeat_task():
    """
    Toggles the configured heartbeat bit mask dynamically at a 500ms cycle.
    """

    print(">>> Heartbeat Monitor Active...")
    is_on = False
    while True:
        is_on = not is_on
        set_bits = LED_HEARTBEAT_MASK if is_on else 0x00
        led_apply(LED_HEARTBEAT_MASK, set_bits)
        await asyncio.sleep(0.5)


# Global State Shadows (Mimicking C Global Variables)
led_state = 0x00

asyncio.run(heartbeat_task())
