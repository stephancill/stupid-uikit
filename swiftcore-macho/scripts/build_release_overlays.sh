#!/bin/bash
# Build the Darwin SDK overlays the swift.org release package does not carry
# (Darwin, _DarwinFoundation1/2/3, _errno, ObjectiveC) against that release's
# runtime, and add them to its artifacts layout beside the fetched dylibs.
#
#   bash swiftcore-macho/scripts/build_release_overlays.sh <artifacts> <corelibs-foundation>
#
#   artifacts            fetch_release_runtime.sh's output (swift-macosx/<arch>/, modules)
#   corelibs-foundation  a swift-corelibs-foundation checkout (its CoreFoundation
#                        headers go into the SDK; phase2's contract pin is
#                        scratch/ud-guest-x86_64/cf)
#
# The SDK is the one build_stdlib.sh compiles the overlays against
# (stage_sdk.sh: machorun's sdk/, objc4, CoreFoundation, overlay-darwin).
# phase2's *-fe-clang FE sysroot is not a substitute: its Darwin and
# _DarwinFoundation Clang modules form a cycle (errno.h -> sys/wait.h).
#
# build_stdlib.sh builds the same set inside a full stdlib cross-build. Here
# the stdlib is the release's, so only the overlays are compiled:
#   - the five shells and ObjectiveC through build_sdk_overlays.sh, given a
#     resource dir assembled from the release modules and the compiler's own
#     shims;
#   - Darwin from the Swift 6.2.4 stdlib's Platform/ sources, the release the
#     x86_64 artifact was built from (Swift 6.4 ships the Darwin overlay only in
#     Apple's SDKs). Flags follow that Platform/CMakeLists.txt and the x86_64
#     artifact's interface header.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck disable=SC1091
. "$SCRIPT_DIR/guest_arch.inc"

ART=$(cd "${1:?usage: build_release_overlays.sh <artifacts> <corelibs-foundation>}" && pwd)
SCF=$(cd "${2:?usage: build_release_overlays.sh <artifacts> <corelibs-foundation>}" && pwd)
ARCH=$SWIFTCORE_DARWIN_ARCH
triple=$SWIFTCORE_MODULE_TRIPLE
target=$SWIFTCORE_CLANG_TARGET
SWIFTC=${SWIFTC:-$TC/bin/swiftc}
# The Swift 6.2.4 tag's commit (SWIFT_PIN_COMMIT in guest_arch.inc defaults to it).
DARWIN_SRC_COMMIT=ee343b46aef81c3ac7c5d7960cb35a41a88c5a9b
DARWIN_SOURCES=(stdlib/public/Platform/Platform.swift stdlib/public/Platform/TiocConstants.swift
  stdlib/public/Platform/POSIXError.swift stdlib/public/Platform/MachError.swift
  stdlib/public/Platform/Darwin.swift.gyb stdlib/public/Platform/tgmath.swift.gyb
  utils/gyb.py utils/gyb_stdlib_support.py utils/SwiftIntTypes.py utils/SwiftFloatingPointTypes.py
  utils/availability-macros.def)

[ -f "$ART/swift-macosx/$ARCH/libswiftCore.dylib" ] || { echo "build_release_overlays: no $ARCH runtime in $ART" >&2; exit 2; }
[ -d "$SCF/Sources/CoreFoundation/include" ] || { echo "build_release_overlays: no CoreFoundation headers in $SCF" >&2; exit 2; }
# clangxx_darwin_link.py links with the toolchain's clang++ when TC is exported, as build_stdlib.sh does.
export TC

# A resource dir in the stdlib build-tree shape build_sdk_overlays.sh reads.
B=$ART/.overlay-build
rm -rf "$B"
mkdir -p "$B/lib/swift/macosx/$ARCH" "$B/work"
ln -s "$SCF" "$B/work/scf"
W=$B/work bash "$SCRIPT_DIR/stage_sdk.sh"
SDK=$(cd "$B/work/sdk/MacOSX.sdk" && pwd -P)
cp -R "$ART/swift-macosx/"*.swiftmodule "$B/lib/swift/macosx/"
cp "$ART/swift-macosx/$ARCH/"*.dylib "$B/lib/swift/macosx/$ARCH/"
cp -R "$TC/lib/swift/shims" "$B/lib/swift/shims"
# Clang's builtin headers (stddef.h, stdarg.h, ...) come from <resource-dir>/clang, ahead of the
# SDK's; machorun's sdk/ stddef.h, for one, expects them to win.
ln -s "$(readlink -f "$TC/lib/swift/clang")" "$B/lib/swift/clang"

echo "== SDK overlay shells and ObjectiveC"
W=$B/work B=$B SDK=$SDK SWIFTC=$SWIFTC SWIFTCORE_DARWIN_ARCH=$ARCH \
  bash "$SCRIPT_DIR/build_sdk_overlays.sh" "$ARCH" "$B"

echo "== Darwin from Swift 6.2.4 stdlib/public/Platform"
src=$B/darwin-src
for f in "${DARWIN_SOURCES[@]}"; do
  mkdir -p "$src/$(dirname "$f")"
  curl -fsSL -o "$src/$f" "https://raw.githubusercontent.com/swiftlang/swift/$DARWIN_SRC_COMMIT/$f"
done
gen=$B/darwin-gen
mkdir -p "$gen"
for g in Darwin tgmath; do
  python3 "$src/utils/gyb.py" -DCMAKE_SIZEOF_VOID_P=8 --line-directive '' \
    -o "$gen/$g.swift" "$src/stdlib/public/Platform/$g.swift.gyb"
done
out_lib=$B/lib/swift/macosx/$ARCH
out_mod=$B/lib/swift/macosx
mkdir -p "$out_mod/Darwin.swiftmodule"
# @available(SwiftStdlib X.Y, *): the stdlib build defines these from availability-macros.def.
availability=()
while IFS= read -r line; do
  case "$line" in '#'* | '') continue ;; esac
  availability+=(-Xfrontend -define-availability -Xfrontend "$line")
done <"$src/utils/availability-macros.def"
[ "${#availability[@]}" -gt 0 ] || { echo "build_release_overlays: no availability macros" >&2; exit 2; }
"$SWIFTC" -c -sdk "$SDK" -target "$target" \
  -resource-dir "$B/lib/swift" -I "$B/lib/swift/shims" \
  -tools-directory "$(dirname "$SWIFTC")" -module-cache-path "$B/work/modcache" \
  -parse-as-library -O -wmo -enable-library-evolution -autolink-force-load \
  -module-name Darwin -module-link-name swiftDarwin -I "$out_mod" -swift-version 5 \
  -library-level api -enforce-exclusivity=unchecked \
  -no-link-objc-runtime -runtime-compatibility-version none -DSWIFT_ENABLE_REFLECTION \
  -Xcc -I"$SDK/usr/include" "${availability[@]}" \
  -Xfrontend -disable-objc-attr-requires-foundation-module \
  -Xfrontend -disable-implicit-concurrency-module-import \
  -Xfrontend -disable-implicit-string-processing-module-import \
  -Xfrontend -disable-autolinking-runtime-compatibility-concurrency \
  -emit-module -emit-module-path "$out_mod/Darwin.swiftmodule/$triple.swiftmodule" \
  -emit-module-interface-path "$out_mod/Darwin.swiftmodule/$triple.swiftinterface" \
  -o "$B/work/Darwin.o" \
  "$src/stdlib/public/Platform/Platform.swift" "$src/stdlib/public/Platform/TiocConstants.swift" \
  "$src/stdlib/public/Platform/POSIXError.swift" "$src/stdlib/public/Platform/MachError.swift" \
  "$gen/Darwin.swift" "$gen/tgmath.swift"
rm -f "$out_mod/Darwin.swiftmodule/$triple.swiftsourceinfo"
# build_sdk_overlays.sh built the compiler-rt archive at $B/libclang_rt.osx.a.
SWIFTCORE_COMPILER_RT_OSX=$B/libclang_rt.osx.a python3 "$SCRIPT_DIR/clangxx_darwin_link.py" -target "$target" -isysroot "$SDK" -fuse-ld=lld \
  -B /usr/lib/llvm-18/bin -shared -Wl,-install_name,/usr/lib/swift/libswiftDarwin.dylib \
  -o "$out_lib/libswiftDarwin.dylib" "$B/work/Darwin.o" -L "$out_lib" -lswiftCore -lSystem -lobjc

echo "== into $ART"
for lib in libswiftDarwin libswift_DarwinFoundation1 libswift_DarwinFoundation2 libswift_DarwinFoundation3 \
  libswift_errno libswiftObjectiveC; do
  [ -f "$out_lib/$lib.dylib" ] || { echo "build_release_overlays: $lib.dylib was not built" >&2; exit 2; }
  cp -f "$out_lib/$lib.dylib" "$ART/swift-macosx/$ARCH/"
done
for m in Darwin _DarwinFoundation1 _DarwinFoundation2 _DarwinFoundation3 _errno ObjectiveC; do
  mkdir -p "$ART/swift-macosx/$m.swiftmodule"
  cp -f "$out_mod/$m.swiftmodule/$triple".* "$ART/swift-macosx/$m.swiftmodule/"
done
{
  echo "overlays built by build_release_overlays.sh against $SDK"
  echo "darwin-sources swift@$DARWIN_SRC_COMMIT"
  (cd "$ART" && find swift-macosx -type f | LC_ALL=C sort | xargs sha256sum)
} >"$ART/OVERLAYS.txt"
echo "build_release_overlays: 6 overlays ($ARCH) in $ART"
