#
# This file is the oled-scripts recipe.
#

SUMMARY = "Simple oled-scripts application"
SECTION = "PETALINUX/apps"
LICENSE = "MIT"
LIC_FILES_CHKSUM = "file://${COMMON_LICENSE_DIR}/MIT;md5=0835ade698e0bcf8506ecda2f7b4f302"

SRC_URI = " \
	file://load_oled \
	file://unload_oled \
	file://logo.bin \
	"

S = "${WORKDIR}"

# 1. Inherit the SysVinit script management system
inherit update-rc.d

# 2. Tell the system which script to register and when to execute it (Runlevel 5, order 99)
INITSCRIPT_NAME = "load_oled"
INITSCRIPT_PARAMS = "start 99 5 . stop 20 0 1 6 ."

do_install() {
    install -d ${D}${bindir}
    install -d ${D}${datadir}/oled
    # 3. Create the directory for boot initialization scripts
    install -d ${D}${sysconfdir}/init.d

    install -m 0755 ${S}/load_oled ${D}${bindir}/load_oled
    install -m 0755 ${S}/unload_oled ${D}${bindir}/unload_oled
    install -m 0644 ${S}/logo.bin ${D}${datadir}/oled/logo.bin

    # 4. Install a duplicate of the execution script into the boot scripts folder
    install -m 0755 ${S}/load_oled ${D}${sysconfdir}/init.d/load_oled
}

FILES:${PN} += " \
    ${bindir}/load_oled \
    ${bindir}/unload_oled \
    ${datadir}/oled/logo.bin \
    ${sysconfdir}/init.d/load_oled \
"

