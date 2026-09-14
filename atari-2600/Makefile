# Makefile -- a convenience wrapper. build.sh is the real build.
#
# Standalone, like ../intv/ and ../coleco/: the shared clients/ core assumes a
# keyboard and kilobytes of buffers, and this console has a joystick, three
# buttons and 128 bytes of RAM.

ENDPOINT ?= https://lobby.fujinet.online/
PLATFORM ?= a2600
FN2600   ?= $(HOME)/Workspace/fujinet-firmware/pico/atari-2600
MAME_DIR ?= $(HOME)/Workspace/mame
SECS     ?= 60

SRC := $(wildcard src/*.asm src/*.inc)
ENV  = ENDPOINT="$(ENDPOINT)" PLATFORM="$(PLATFORM)" FN2600="$(FN2600)"

.PHONY: all layout run runlayout shot colours frames cursor nametest boottest \
        pagetest probe emu install clean

all: build/lobby.bin
build/lobby.bin: $(SRC) build.sh tools/checkbanks.py tools/mktail.py
	$(ENV) ./build.sh

# The screen with no network at all: the kernel, the colours and the geometry.
layout: build/layout.bin
build/layout.bin: $(SRC) build.sh
	$(ENV) ./build.sh layout

# Interactive, in a window.
run: all
	MAME=$(MAME_DIR) ./run.sh lobby
runlayout: layout
	MAME=$(MAME_DIR) ./run.sh layout

# Headless.
#
# NOT -nothrottle for anything that talks to a server: a round trip is wall
# clock and an unthrottled run outruns it. FAST=1 is only for the layout ROM,
# which waits on nothing.
shot: layout
	MAME=$(MAME_DIR) FAST=1 SECS=10 ./run.sh layout shot

colours: all
	MAME=$(MAME_DIR) SECS=$(SECS) ./run.sh lobby colours
frames: all
	MAME=$(MAME_DIR) SECS=$(SECS) ./run.sh lobby frames
cursor: layout
	MAME=$(MAME_DIR) FAST=1 SECS=20 ./run.sh layout cursor
pagetest: all
	MAME=$(MAME_DIR) SECS=$(SECS) ./run.sh lobby pagetest
probe: all
	MAME=$(MAME_DIR) SECS=$(SECS) ./run.sh lobby probe

# THESE TWO WRITE TO A REAL FUJINET. nametest changes the username appkey
# every client on the machine shares and prints what it found so it can be put
# back; boottest rewrites the last host slot and mounts something.
nametest: all
	MAME=$(MAME_DIR) SECS=120 ./run.sh lobby nametest
boottest: all
	MAME=$(MAME_DIR) SECS=120 ./run.sh lobby boottest

# Re-graft the cartridge device into MAME. Needed after ANY edit to a shared
# firmware source -- MAME compiles its own copies.
emu:
	$(FN2600)/emu/apply.sh
	$(MAKE) -C $(MAME_DIR) -j$$(nproc) NOWERROR=1 REGENIE=1

# Where fujinet-config's LOBBY entry expects to find this.
install: all
	@echo "copy build/lobby.bin to your TNFS host as /a2600/lobby.bin"
	@echo "  (fujinet-config/atari-2600/src/hosts.asm:LBPATH)"

clean:
	rm -rf build
