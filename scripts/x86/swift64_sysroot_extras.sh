#!/usr/bin/env bash
# Adds what a Swift 6.4 guest compile needs beyond the staged runtime to the macOS-guest sysroot
# (stage_fe_sysroot.sh runs it): the SwiftShims Clang module and SwiftOnoneSupport (module +
# dylib), which -Onone code imports.
#
#   W=<tree> SYS=<sysroot> bash scripts/x86/swift64_sysroot_extras.sh
set -euo pipefail
W=${W:?set W to the openuikit tree}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=common.inc
. "$HERE/common.inc"
# shellcheck disable=SC1091
. "$W/full/scripts/guest_arch.inc"
SYS=${SYS:-$W/scratch/sysroot_fe4${FULL_OUT_SUFFIX}}
ART=$(phase2_swiftcore_artifacts "$W")/swift-macosx
ROOT=$W/scratch/mrroot_full${FULL_OUT_SUFFIX}/darwin/usr/lib/swift
TRIPLE=$ARCH-apple-macos
cd "$W"

# Swift 6.4 on a Linux host does not search <resource-dir>/shims for Darwin targets, and the Swift
# module imports the SwiftShims Clang module. Clang finds usr/include/<dir>/module.modulemap itself.
# The headers are the compiler's own (the toolchain resource dir), the release the runtime is.
SHIMS=$(cd "$(dirname "$(readlink -f "$(command -v swiftc)")")/../lib/swift/shims" && pwd)
[ -f "$SHIMS/module.modulemap" ] || { echo "swift64_sysroot_extras: no SwiftShims at $SHIMS" >&2; exit 2; }
if [ ! -f "$SYS/usr/include/SwiftShims/module.modulemap" ]; then
    mkdir -p "$SYS/usr/include/SwiftShims"
    cp -a "$SHIMS/." "$SYS/usr/include/SwiftShims/"
    echo "staged SwiftShims into the sysroot from $SHIMS"
fi

mkdir -p "$SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule" "$ROOT"
if [ -f "$ART/$ARCH/libswiftSwiftOnoneSupport.dylib" ]; then
    # The swift.org release runtime carries it (fetch_release_runtime.sh).
    cp -f "$ART/SwiftOnoneSupport.swiftmodule/$TRIPLE".* "$SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule/"
    cp -f "$ART/$ARCH/libswiftSwiftOnoneSupport.dylib" "$SYS/usr/lib/swift/"
    cp -f "$ART/$ARCH/libswiftSwiftOnoneSupport.dylib" "$ROOT/"
    echo "staged SwiftOnoneSupport from $ART"
else
    # The x86_64 cross-built artifacts do not include it. Only SwiftOnoneSupport is added: copying
    # the artifact overlay modules (_Concurrency etc.) in as well breaks the build, because their
    # binary modules are rejected and their interfaces do not parse.
    TARGET=$TRIPLE'15.0'
    work=$(mktemp -d /tmp/onone.XXXXXX)
    curl -fsSL -o "$work/SwiftOnoneSupport.swift" \
        https://raw.githubusercontent.com/swiftlang/swift/swift-6.2.4-RELEASE/stdlib/public/SwiftOnoneSupport/SwiftOnoneSupport.swift
    # Flags from stdlib/public/SwiftOnoneSupport/CMakeLists.txt (Swift 6.2.4).
    swiftc -target "$TARGET" -sdk "$SYS" -module-name SwiftOnoneSupport -parse-stdlib -parse-as-library -O -language-mode 5 \
        -Xllvm -sil-inline-generics=false -Xfrontend -validate-tbd-against-ir=none \
        -Xfrontend -check-onone-completeness -Xfrontend -disable-access-control \
        -enable-library-evolution -runtime-compatibility-version none \
        -emit-module -emit-module-path "$SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule/$TRIPLE.swiftmodule" \
        -emit-module-interface-path "$SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule/$TRIPLE.swiftinterface" \
        -c -o "$work/SwiftOnoneSupport.o" "$work/SwiftOnoneSupport.swift"

    # Link like swiftcore-macho/scripts/link_macho_dylib.sh: clang driver for Darwin, Ubuntu's ld64.lld-18.
    clang-18 -target "$TARGET" -isysroot "$SYS" -fuse-ld=lld -B /usr/lib/llvm-18/bin \
        -dynamiclib -install_name /usr/lib/swift/libswiftSwiftOnoneSupport.dylib \
        -compatibility_version 1 -current_version 1 \
        -L"$SYS/usr/lib" -L"$SYS/usr/lib/swift" -nostdlib "$work/SwiftOnoneSupport.o" \
        -lSystem -lswiftCore -Wl,-undefined,dynamic_lookup \
        -o "$work/libswiftSwiftOnoneSupport.dylib"
    cp "$work/libswiftSwiftOnoneSupport.dylib" "$SYS/usr/lib/swift/"
    cp "$work/libswiftSwiftOnoneSupport.dylib" "$ROOT/"
    rm -rf "$work"
fi
file "$ROOT/libswiftSwiftOnoneSupport.dylib"
llvm-nm-18 -gU "$ROOT/libswiftSwiftOnoneSupport.dylib" | wc -l
[ "$(id -u)" = 0 ] && chown -R ubuntu:ubuntu "$SYS" "$ROOT" || true
