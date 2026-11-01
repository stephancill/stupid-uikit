# guest_arch.inc -- Swift/UI guest triple for this host. Sourced, not executed.
#
# Distinct from machorun/scripts/guest_arch.inc (macos11): FoundationEssentials
# modules declare a macOS 15 minimum, and the full/swiftui gates compile at
# macos15.0. Do not unify the two numbers.
#
# Every architecture writes beside the historical unsuffixed trees
# (build/full, scratch/mrroot, scratch/sysroot_fe4, the durable OpenCombine
# export/), which the upstream arm64 route built from an EC2 operator box:
# x86_64 writes build/full-x86_64, scratch/mrroot_full-x86_64, ...; an aarch64
# Linux host bootstrapped by scripts/x86/phase2.sh writes build/full-arm64,
# scratch/mrroot_full-arm64, .... Never overwrite one architecture's package
# with another's, and never weaken an arm64 hash gate to make another run pass.
if [ -z "${TARGET:-}" ]; then
    case "$(uname -m)" in
        x86_64)        TARGET=x86_64-apple-macos15.0 ;;
        aarch64|arm64) TARGET=arm64-apple-macos15.0 ;;
        *) echo "guest_arch: unsupported host $(uname -m)" >&2; exit 1 ;;
    esac
fi
case "$TARGET" in
    x86_64-*)          ARCH=x86_64; FULL_OUT_SUFFIX=-x86_64 ;;
    arm64-*|aarch64-*) ARCH=arm64;  FULL_OUT_SUFFIX=-arm64 ;;
    *) echo "guest_arch: cannot derive arch from TARGET=$TARGET" >&2; exit 1 ;;
esac
# The Darwin runtime under machorun (scratch/mrroot*, the OpenCombine export)
# is one per architecture whatever the OS in TARGET: an iOS-simulator build
# copies it and retargets the copies (build_full.sh retarget_runtime_macho).
RUNTIME_SOURCE_SUFFIX=$FULL_OUT_SUFFIX
# OS in TARGET: macOS (default) or the iOS simulator (LC_BUILD_VERSION
# platform 7, so `#if os(iOS)` app code compiles in). GUEST_MINOS is the
# triple's version; GUEST_LINK_PLATFORM is ld64's -platform_version name.
case "$TARGET" in
    *-apple-macos*)
        GUEST_LINK_PLATFORM=macos
        GUEST_MINOS=${TARGET#*-apple-macos}; GUEST_MINOS=${GUEST_MINOS#x}
        GUEST_OS_TRIPLE=apple-macos ;;
    *-apple-ios*-simulator)
        GUEST_LINK_PLATFORM=ios-simulator
        GUEST_MINOS=${TARGET#*-apple-ios}; GUEST_MINOS=${GUEST_MINOS%-simulator}
        GUEST_OS_TRIPLE=apple-ios-simulator
        # iOS-simulator outputs live beside the macOS ones
        # (build/full-arm64-iossim, scratch/sysroot_fe4-x86_64-iossim, ...).
        # The upstream arm64 iOS route (full/iostarget/ios_guest.sh) passes
        # every path explicitly.
        FULL_OUT_SUFFIX=$FULL_OUT_SUFFIX-iossim ;;
    *) echo "guest_arch: cannot derive the OS from TARGET=$TARGET" >&2; exit 1 ;;
esac
case "$GUEST_MINOS" in
    [0-9]*.[0-9]*) ;;
    *) echo "guest_arch: TARGET=$TARGET carries no OS version (want e.g. 15.0)" >&2; exit 1 ;;
esac
# ld64 -arch flag matches ARCH. clang -target is TARGET.
LD64_ARCH="$ARCH"
# Swift emits module files as ${ARCH}-apple-macos.swiftmodule (no OS version),
# ${ARCH}-apple-ios-simulator.swiftmodule for the simulator.
SWIFT_MODULE_TRIPLE="${ARCH}-${GUEST_OS_TRIPLE}"
# llvm-otool-18 -hv CPU column: ARM64 or X86_64.
case "$ARCH" in
    x86_64) OTOOL_CPU=X86_64 ;;
    arm64)  OTOOL_CPU=ARM64 ;;
esac
# Compile sysroot beside the unsuffixed upstream tree (scratch/sysroot_fe4-<arch>).
SYSROOT_SUFFIX=$FULL_OUT_SUFFIX
# The durable OpenCombine export/ is upstream arm64; cold-builds land in export-<arch>/.
OPENCOMBINE_EXPORT_SUFFIX=$RUNTIME_SOURCE_SUFFIX
# Child processes (widget env-prepare / scripts/env/prepare.py) must inherit
# the suffix; otherwise they resolve the unsuffixed upstream arm64 trees.
export FULL_OUT_SUFFIX
export TARGET ARCH SYSROOT_SUFFIX OPENCOMBINE_EXPORT_SUFFIX
export LD64_ARCH SWIFT_MODULE_TRIPLE OTOOL_CPU
export RUNTIME_SOURCE_SUFFIX GUEST_LINK_PLATFORM GUEST_MINOS GUEST_OS_TRIPLE

require_macho_cpu() {
    local f=$1 label=${2:-$1}
    llvm-otool-18 -hv "$f" 2>/dev/null \
        | grep -Eq "MH_MAGIC_64[[:space:]]+${OTOOL_CPU}" \
        || { echo "guest_arch: $label is not ${OTOOL_CPU} Mach-O: $f" >&2; return 1; }
}
