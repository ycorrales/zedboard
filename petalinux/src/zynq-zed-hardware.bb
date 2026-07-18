#
# This file is the zynq-zed-hardware recipe.
#

SUMMARY = "Multi-threaded secure system monitoring background engine and REST API for ZedBoard"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = "file://zynq-zed-hardware.c \
           file://zynq-zed-hw.sh \
           file://Makefile"

S = "${WORKDIR}"
LDFLAGS += "-lpthread"

inherit update-rc.d

INITSCRIPT_NAME = "zynq-zed-hw.sh"
INITSCRIPT_PARAMS = "defaults 99"

do_compile() {
    oe_runmake
}

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${sysconfdir}/init.d

    install -m 0755 zynq-zed-hardware ${D}${bindir}/zynq-zed-hardware
    install -m 0755 zynq-zed-hw.sh ${D}${sysconfdir}/init.d/zynq-zed-hw.sh
}

FILES_${PN} += "${bindir}/zynq-hardware-app \
                ${sysconfdir}/init.d/zynq-zed-hw.sh"

