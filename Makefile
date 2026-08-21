Z80_AS ?= pasmo
PYTHON ?= python3
BUILD_DIR := build
BASE_SRC := src/monitor4k.asm
DSI_SRC := src/dsi_boot.inc
GENERATOR := tools/make_dsi_monitor.py
SRC := $(BUILD_DIR)/monitor4k-dsi.asm
RAW := $(BUILD_DIR)/monitor.raw.bin
SYM := $(BUILD_DIR)/monitor.sym
ROM4K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_4K.bin
ROM8K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_28C64.bin

.PHONY: all clean verify

all: $(ROM4K) $(ROM8K)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(SRC): $(BASE_SRC) $(DSI_SRC) $(GENERATOR) | $(BUILD_DIR)
	$(PYTHON) $(GENERATOR) --base $(BASE_SRC) --dsi $(DSI_SRC) --output $(SRC)

$(RAW): $(SRC)
	$(Z80_AS) --bin $(SRC) $(RAW) $(SYM)

$(ROM4K) $(ROM8K): $(RAW) third_party/CDBL.HEX tools/build_image.py
	$(PYTHON) tools/build_image.py --monitor $(RAW) --cdbl third_party/CDBL.HEX --outdir $(BUILD_DIR)

verify: all
	$(PYTHON) tools/build_image.py --monitor $(RAW) --cdbl third_party/CDBL.HEX --outdir $(BUILD_DIR) --verify-only

clean:
	rm -rf $(BUILD_DIR)
