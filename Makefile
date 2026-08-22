Z80_AS ?= pasmo
PYTHON ?= python3
BUILD_DIR := build

SRC := src/monitor4k.asm
RAW := $(BUILD_DIR)/monitor.raw.bin
SYM := $(BUILD_DIR)/monitor.sym

FDC_SRC := src/fdc3712rom.asm
FDC_BIN := $(BUILD_DIR)/fdc3712rom.bin
FDC_SYM := $(BUILD_DIR)/fdc3712rom.sym

EXT_SRC := src/monext.asm
EXT_BIN := $(BUILD_DIR)/monext.bin
EXT_SYM := $(BUILD_DIR)/monext.sym

ROM4K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_4K.bin
ROM8K := $(BUILD_DIR)/IMSAI_TARGET_MONITOR_28C64.bin

.PHONY: all clean verify

all: $(ROM4K) $(ROM8K)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(RAW): $(SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(SRC) $(RAW) $(SYM)

$(FDC_BIN): $(FDC_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(FDC_SRC) $(FDC_BIN) $(FDC_SYM)

$(EXT_BIN): $(EXT_SRC) | $(BUILD_DIR)
	$(Z80_AS) --bin $(EXT_SRC) $(EXT_BIN) $(EXT_SYM)

$(ROM4K) $(ROM8K): $(RAW) $(FDC_BIN) $(EXT_BIN) tools/build_image.py
	$(PYTHON) tools/build_image.py --monitor $(RAW) --fdc $(FDC_BIN) --ext $(EXT_BIN) --outdir $(BUILD_DIR)

verify: all
	$(PYTHON) tools/build_image.py --monitor $(RAW) --fdc $(FDC_BIN) --ext $(EXT_BIN) --outdir $(BUILD_DIR) --verify-only

clean:
	rm -rf $(BUILD_DIR)
