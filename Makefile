Z80_AS ?= pasmo
PYTHON ?= python3
BUILD_DIR := build
SRC := src/monitor4k.asm
RAW := $(BUILD_DIR)/monitor.raw.bin
SYM := $(BUILD_DIR)/monitor.sym
ROM4K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_4K.bin
ROM8K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_28C64.bin

.PHONY: all clean verify

all: $(ROM4K) $(ROM8K)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(RAW): $(SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(SRC) $(RAW) $(SYM)

$(ROM4K) $(ROM8K): $(RAW) third_party/CDBL.HEX tools/build_image.py
	$(PYTHON) tools/build_image.py --monitor $(RAW) --cdbl third_party/CDBL.HEX --outdir $(BUILD_DIR)

verify: all
	$(PYTHON) tools/build_image.py --monitor $(RAW) --cdbl third_party/CDBL.HEX --outdir $(BUILD_DIR) --verify-only

clean:
	rm -rf $(BUILD_DIR)
