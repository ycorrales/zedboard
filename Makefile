
CERNBOX_DIR := /home/maps/cernbox/Course_and_Tutorial/FPGAExamples/VHDL/Zedboard
VIV_DIR := $(CURDIR)/vivado
VITIS_DIR := $(CURDIR)/vitis


clean_vivado:
	@cd $(VIV_DIR) && rm -rf *.jou *.log Projects SimulationLib NA hw.gen .Xil

sync_viv_bin:
	@rsync -avu --delete $(VIV_DIR)/bin $(CERNBOX_DIR)/vivado/.

sync_vitis_bin:
	@rsync -avu --delete $(VITIS_DIR)/bin $(CERNBOX_DIR)/vitis/.
