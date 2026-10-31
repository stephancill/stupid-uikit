#!/usr/bin/env bash
# heap_xi_guest.sh -- run IOSHeapXIGuestProbe (second-level heap-object extra
# inhabitants on the x86_64 iOS-simulator guest; full/shims/swiftcorepatch.c)
# under machorun, after `TARGET=x86_64-apple-ios26.0-simulator
# bash full/scripts/build_full.sh` built it.
#
#   bash full/iostarget/heap_xi_guest.sh [TREE] [--unpatched]
#
# --unpatched keeps the runtime's macOS encoding (reproduces the crash).
# Prints the probe's PASS/FAIL lines; exits 0 only on
# IOS_HEAP_XI_GUEST_PROBE=PASS.
set -euo pipefail
W=$(CDPATH= cd -- "${1:-$(dirname -- "${BASH_SOURCE[0]}")/../..}" && pwd -P)
extra=()
[ "${2:-}" = --unpatched ] && extra=(OPENUIKIT_KEEP_MACOS_HEAP_EXTRA_INHABITANTS=1)
OUT=$W/build/full-x86_64-iossim
ROOTDIR=$W/scratch/mrroot_full-x86_64-iossim
PROBE=$OUT/IOSHeapXIGuestProbe
[ -x "$PROBE" ] || { echo "heap_xi_guest: no $PROBE (build_full on the iOS triple first)" >&2; exit 2; }
HOME_DIR=$(mktemp -d)
trap 'rm -rf "$HOME_DIR"' EXIT
log=$(cd "$OUT" && env "${extra[@]}" HOME="$HOME_DIR" MACHORUN_ROOT="$ROOTDIR" LD_LIBRARY_PATH="$OUT/host" \
    LD_PRELOAD="$OUT/host/libOpenDispatchHost.so:$OUT/host/libOpenFoundationInternationalizationHost.so:$OUT/host/libOpenURLTransportHost.so:$OUT/host/libOpenRelativeTimeHost.so" \
    "$ROOTDIR/machorun" "$PROBE" 2>&1) || { printf '%s\n' "$log" | grep -v '^objc\[' | tail -40; echo "heap_xi_guest: guest exited non-zero" >&2; exit 1; }
printf '%s\n' "$log" | grep -E '^(PASS|FAIL) |IOS_HEAP_XI_GUEST_PROBE='
printf '%s\n' "$log" | grep -q '^IOS_HEAP_XI_GUEST_PROBE=PASS$'
