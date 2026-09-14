#!/usr/bin/env bash
# run.sh -- run a built image in MAME.
#
#   ./run.sh <image> [lua-script]
#
# With a script it runs headless and exits; without one it opens a window.
#
# The cartridge device lives in the firmware tree (see $FN2600/emu/apply.sh,
# which grafts it into MAME). This port's own harnesses live in emu/ here.
#
# Four environment facts this wraps, each of which costs time to rediscover:
#
#   - MAME must run FROM ITS OWN TREE or -autoboot_script is silently ignored.
#   - SDL_VIDEODRIVER=dummy is required wherever there is no DISPLAY; without
#     it MAME dies with "Could not initialize SDL No available video device"
#     even under -video none, because SDL is brought up before the video
#     backend is chosen.
#   - fujinet-pc's BoIP listener takes ONE client (backlog 1), so a MAME left
#     running silently starves the next run and the symptom is a hang, not an
#     error. Kill any stray first.
#   - NOT -nothrottle by default. Anything that waits on a server waits on
#     WALL CLOCK, and an unthrottled run outruns it. FAST=1 is only for
#     screens that wait on nothing, which is what the layout ROM is.
set -euo pipefail
cd "$(dirname "$0")"
HERE=$(pwd)

IMAGE=${1:?usage: run.sh <image> [lua-script]}
SCRIPT=${2:-}
MAME=${MAME:-$HOME/Workspace/mame}
SNAP=${SNAP:-$HERE/build/snap}
FN2600=${FN2600:-$HOME/Workspace/fujinet-firmware/pico/atari-2600}

# The layout ROM talks to the mailbox only to compose text, but it still needs
# the cartridge device: the text planes ARE the cartridge.
SLOT=${SLOT:-fujinet}

BIN="$HERE/build/$IMAGE.bin"
[ -f "$BIN" ] || { echo "run.sh: no build/$IMAGE.bin -- run make" >&2; exit 1; }

pkill -f "mame a2600" 2>/dev/null || true
mkdir -p "$SNAP"

args=(a2600 -cartslot "$SLOT" -cart "$BIN" -snapshot_directory "$SNAP")

# Harnesses write their artefacts next to the build, not into the MAME tree we
# have to cd into, and require() shared modules from this port's emu/ first,
# then the firmware tree's, which is where vcsfont.lua lives.
export DRIVE_EXPECT="${DRIVE_EXPECT:-$HERE/build/expect.txt}"
export A2600_EMU="$HERE/emu"
export A2600_FWEMU="$FN2600/emu"

# DRIVE_LUA is dofile()'d by a harness, and MAME is running from ITS OWN tree
# by then -- so a relative path resolves against the MAME directory and the
# script dies with "cannot open emu/whatever.lua". Resolve it here, where the
# caller's idea of "here" is still true. A bare name means this port's emu/.
if [ -n "${DRIVE_LUA:-}" ]; then
    case "$DRIVE_LUA" in
        /*) ;;
        */*) DRIVE_LUA="$HERE/$DRIVE_LUA" ;;
         *) DRIVE_LUA="$HERE/emu/$DRIVE_LUA.lua" ;;
    esac
    [ -f "$DRIVE_LUA" ] || {
        echo "run.sh: no driver at $DRIVE_LUA" >&2; exit 1; }
    export DRIVE_LUA
fi

if [ -n "$SCRIPT" ]; then
    if [ -f "$HERE/emu/$SCRIPT.lua" ]; then
        LUA="$HERE/emu/$SCRIPT.lua"
    elif [ -f "$FN2600/emu/$SCRIPT.lua" ]; then
        LUA="$FN2600/emu/$SCRIPT.lua"
    else
        echo "run.sh: no harness '$SCRIPT.lua' in emu/ or $FN2600/emu/" >&2
        exit 1
    fi
    args+=(-autoboot_script "$LUA" -video none -sound none
           -seconds_to_run "${SECS:-10}")
    [ -n "${FAST:-}" ] && args+=(-nothrottle)
fi

[ -n "${DISPLAY:-}" ] || export SDL_VIDEODRIVER=dummy

cd "$MAME"
exec ./mame "${args[@]}"
