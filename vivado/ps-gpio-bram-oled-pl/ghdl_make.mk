UTILS_DIR := $(abspath $(CURDIR)/../../../../../utils)

SRC_DIR := $(CURDIR)/vivado/src
HDL_DIR := $(SRC_DIR)/hdl
SIM_DIR := $(SRC_DIR)/sim

export TB_ENTITY := tb_fibonacci
TIME ?= 1000ns

check-dir:
	@ [ -d "$(UTILS_DIR)" ] || { echo "Error: $(UTILS_DIR) not found!"; exit 1; }

ghdl-%: check-dir
	$(MAKE) -f $(UTILS_DIR)/ghdl_make.mk $* HDL_DIR="$(HDL_DIR)" SIM_DIR="$(SIM_DIR)" SIM_TIME="$(TIME)"

