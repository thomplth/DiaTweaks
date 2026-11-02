CFLAGS := -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter
DYLIB_SOURCES := $(shell find src/dylib -name '*.[hm]')
PASSKEYS := src/dylib/Patches/Passkeys/extension
EXTENSION := $(foreach file,manifest.json page.js bridge.js worker.js,-Wl,-sectcreate,__TEXT,__pk_$(basename $(file)),$(PASSKEYS)/$(file))

all: build/diapatch build/DiaPatches.dylib build/patches.json

# The public keys DiaTweaks releases must be signed with, in ssh-keygen's allowed_signers format.
RELEASE_SIGNERS ?= release-signers
CDHASH = $$(codesign -dvvv $(1) 2>&1 | sed -n 's/^CDHash=//p')

build/diapatch: $(wildcard src/diapatch/*.[hm]) $(RELEASE_SIGNERS) | build
	clang $(CFLAGS) -framework AppKit -framework CoreGraphics -framework Security -Wl,-sectcreate,__TEXT,__signers,$(RELEASE_SIGNERS) -o $@ $(filter %.m,$^)

# The dylib only runs the diapatch it was built with.
build/DiaPatches.dylib: $(DYLIB_SOURCES) $(wildcard $(PASSKEYS)/*) build/diapatch | build
	clang $(CFLAGS) -Isrc/dylib -dynamiclib $(EXTENSION) -DDP_DIAPATCH_CDHASH="\"$(call CDHASH,build/diapatch)\"" -framework Security -framework AppKit -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo -o $@ $(filter %.m,$^)

# The patch list for diatweaks. With DIAPATCH_MANIFEST set, the dylib writes it and exits as it loads, so diapatch never runs.
build/patches.json: build/DiaPatches.dylib build/diapatch
	DIAPATCH_MANIFEST=$@ DYLD_INSERT_LIBRARIES=$< build/diapatch

build:
	mkdir -p $@

test: build/DiaPatches.dylib
	./test.sh

# make patch NAME=HideFooButton starts a new patch in src/dylib/Patches/HideFooButton.
patch:
	@scripts/new-patch "$(NAME)"

clean:
	rm -rf build

.PHONY: all clean test patch
