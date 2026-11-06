CFLAGS := -arch arm64 -mmacosx-version-min=14.0 -fobjc-arc -O2 -Wall -Wextra -Wno-unused-parameter
DYLIB_SOURCES := $(shell find src/dylib -name '*.[hm]')
DYLIB_SWIFT := $(shell find src/dylib -name '*.swift')
SDK := $(shell xcrun --show-sdk-path)
SWIFT_LIB := $(SDK)/usr/lib/swift
# FoundationModels only exists on macOS 26+, so it's weak-linked and Swift's automatic link to it is turned off. An
# older SDK has no FoundationModels at all; Tidy Tabs then builds without it and says so when used.
FOUNDATION_MODELS := $(if $(wildcard $(SDK)/System/Library/Frameworks/FoundationModels.framework),-weak_framework FoundationModels)
SWIFTFLAGS := -target arm64-apple-macos14.0 -O -parse-as-library -wmo -module-name DiaPatchesSwift \
	-Xfrontend -disable-autolink-framework -Xfrontend FoundationModels
PASSKEYS := src/dylib/Patches/Passkeys/extension
EXTENSION := $(foreach file,manifest.json page.js bridge.js worker.js,-Wl,-sectcreate,__TEXT,__pk_$(basename $(file)),$(PASSKEYS)/$(file))

all: build/diapatch build/DiaPatches.dylib build/patches.json

# The public keys DiaTweaks releases must be signed with, in ssh-keygen's allowed_signers format.
RELEASE_SIGNERS ?= release-signers
CDHASH = $$(codesign -dvvv $(1) 2>&1 | sed -n 's/^CDHash=//p')

build/diapatch: $(wildcard src/diapatch/*.[hm]) $(RELEASE_SIGNERS) | build
	clang $(CFLAGS) -framework AppKit -framework CoreGraphics -framework Security -Wl,-sectcreate,__TEXT,__signers,$(RELEASE_SIGNERS) -o $@ $(filter %.m,$^)

build/DiaPatchesSwift.o: $(DYLIB_SWIFT) | build
	xcrun swiftc $(SWIFTFLAGS) -emit-object -o $@ $^

# The dylib only runs the diapatch it was built with.
build/DiaPatches.dylib: $(DYLIB_SOURCES) build/DiaPatchesSwift.o $(wildcard $(PASSKEYS)/*) build/diapatch | build
	clang $(CFLAGS) -Isrc/dylib -dynamiclib $(EXTENSION) -DDP_DIAPATCH_CDHASH="\"$(call CDHASH,build/diapatch)\"" -framework Security -framework AppKit -framework Carbon -framework QuartzCore -framework AVFoundation -framework VideoToolbox -framework CoreMedia -framework CoreVideo \
		-L$(SWIFT_LIB) -Wl,-rpath,/usr/lib/swift $(FOUNDATION_MODELS) -o $@ $(filter %.m %.o,$^)

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
