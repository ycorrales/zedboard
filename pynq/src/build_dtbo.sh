#!/bin/bash
# =====================================================================
# Build and (optionally) load the runtime device-tree overlay.
#
# Run ON THE PYNQ BOARD (dtc ships with PYNQ). Lets you rebind PL
# peripherals to generic-uio without recompiling the PYNQ image.
#
# Usage:
#   ./build_dtbo.sh            # compile zynq_zed.dtso -> zynq_zed.dtbo
#   sudo ./build_dtbo.sh load  # compile, then apply via configfs
#   sudo ./build_dtbo.sh unload
# =====================================================================
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DTSO="$HERE/zynq_zed.dtso"
DTBO="$HERE/zynq_zed.dtbo"
OVL_NAME="zynq_zed_gpio"
CFG="/sys/kernel/config/device-tree/overlays/$OVL_NAME"

compile() {
    # -@ keeps __symbols__ so &label references resolve against the base tree.
    dtc -@ -I dts -O dtb -o "$DTBO" "$DTSO"
    echo "Built $DTBO"
}

case "${1:-build}" in
    build)
        compile
        echo
        echo "To auto-apply via PYNQ, copy next to the bitstream:"
        echo "  sudo cp $DTBO /boot/zynq_zed.dtbo"
        echo "Then Overlay('/boot/zynq_zed.bit') applies it automatically."
        ;;
    load)
        compile
        mkdir -p "$CFG"
        cat "$DTBO" > "$CFG/dtbo"
        echo "Applied overlay '$OVL_NAME'. Check:"
        echo "  cat /proc/interrupts | grep uio"
        echo "  for u in /sys/class/uio/uio*; do echo \$u \$(cat \$u/name); done"
        ;;
    unload)
        [ -d "$CFG" ] && rmdir "$CFG" && echo "Removed overlay '$OVL_NAME'." \
            || echo "Overlay '$OVL_NAME' not loaded."
        ;;
    *)
        echo "Usage: $0 {build|load|unload}" >&2
        exit 1
        ;;
esac
