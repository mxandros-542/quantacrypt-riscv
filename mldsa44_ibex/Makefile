CC ?= cc
PYTHON ?= python3
RV_CC ?= riscv32-unknown-elf-gcc
RV_OBJCOPY ?= $(patsubst %gcc,%objcopy,$(RV_CC))
RV_SIZE ?= $(patsubst %gcc,%size,$(RV_CC))
RV_ARCH ?= rv32imc_zicsr

INCLUDES = -Iinclude -Isrc -Ivendor/dilithium -Iexamples
CORE = src/mldsa44.c src/sign_core.c vendor/dilithium/fips202.c \
       vendor/dilithium/ntt.c vendor/dilithium/packing.c vendor/dilithium/poly.c \
       vendor/dilithium/polyvec.c vendor/dilithium/reduce.c \
       vendor/dilithium/rounding.c vendor/dilithium/symmetric-shake.c
HOST_FLAGS = -std=c11 -O2 -Wall -Wextra -Wpedantic -fwrapv $(CFLAGS)
HOST_OBJECTS = $(addprefix build/host/,$(CORE:.c=.o))
RV_SOURCES = $(CORE) examples/demo.c examples/platform.c platform/ibex/runtime.c
RV_OBJECTS = $(addprefix build/ibex/,$(RV_SOURCES:.c=.o)) build/ibex/platform/ibex/start.o
RV_FLAGS = -std=c11 -Os -g -Wall -Wextra -fwrapv -march=$(RV_ARCH) -mabi=ilp32 \
           -mcmodel=medany -msmall-data-limit=0 -ffreestanding -fno-builtin \
           -ffunction-sections -fdata-sections -fstack-usage -DMLDSA44_IBEX

.PHONY: all test acvp sanitize ibex check-elf clean
all: build/demo

build/host/%.o: %.c
	mkdir -p $(dir $@)
	$(CC) $(INCLUDES) $(HOST_FLAGS) -fPIC -MMD -MP -c $< -o $@

build/demo: $(HOST_OBJECTS) examples/demo.c examples/platform.c
	$(CC) $(INCLUDES) $(HOST_FLAGS) $(HOST_OBJECTS) examples/demo.c examples/platform.c -o $@

build/test_mldsa44: $(HOST_OBJECTS) tests/test_mldsa44.c
	$(CC) $(INCLUDES) $(HOST_FLAGS) $(HOST_OBJECTS) tests/test_mldsa44.c -o $@

build/libmldsa44.so: $(HOST_OBJECTS)
	$(CC) -shared $(HOST_OBJECTS) -o $@

test: build/demo build/test_mldsa44
	./build/demo
	./build/test_mldsa44

acvp: build/libmldsa44.so
	$(PYTHON) tests/test_acvp.py

sanitize:
	mkdir -p build
	$(CC) $(INCLUDES) -std=c11 -O1 -g -Wall -Wextra -fwrapv \
	  -fsanitize=address,undefined -fno-omit-frame-pointer \
	  $(CORE) tests/test_mldsa44.c -o build/test_sanitize
	ASAN_OPTIONS=detect_leaks=1 ./build/test_sanitize

build/ibex/%.o: %.c
	mkdir -p $(dir $@)
	$(RV_CC) $(INCLUDES) $(RV_FLAGS) -MMD -MP -c $< -o $@

build/ibex/platform/ibex/start.o: platform/ibex/start.S
	mkdir -p $(dir $@)
	$(RV_CC) $(INCLUDES) $(RV_FLAGS) -c $< -o $@

build/ibex/mldsa44_demo.elf: $(RV_OBJECTS) platform/ibex/link.ld
	$(RV_CC) $(RV_FLAGS) -nostdlib -nostartfiles -T platform/ibex/link.ld \
	  -Wl,--gc-sections,-Map,build/ibex/mldsa44_demo.map $(LDFLAGS) \
	  $(RV_OBJECTS) -lgcc -o $@
	$(RV_SIZE) $@

build/ibex/mldsa44_demo.bin: build/ibex/mldsa44_demo.elf
	$(RV_OBJCOPY) -O binary $< $@

ibex: build/ibex/mldsa44_demo.elf build/ibex/mldsa44_demo.bin

check-elf: build/ibex/mldsa44_demo.elf
	$(PYTHON) tools/check_elf.py $(patsubst %gcc,%,$(RV_CC))

clean:
	rm -rf build

-include $(HOST_OBJECTS:.o=.d) $(RV_OBJECTS:.o=.d)
