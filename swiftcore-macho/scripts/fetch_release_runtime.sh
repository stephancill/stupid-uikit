#!/bin/bash
# Stage the swift.org release's prebuilt Darwin runtime in the artifacts layout
# (swift-macosx/<arch>/*.dylib, swift-macosx/<Module>.swiftmodule/<arch>-*),
# instead of cross-building the stdlib from source (build_stdlib.sh).
#
#   bash swiftcore-macho/scripts/fetch_release_runtime.sh [OUT]
#
#   OUT                 default swiftcore-macho/build/release-runtime (git-ignored)
#   SWIFTCORE_DARWIN_ARCH  arm64 (default on aarch64) or x86_64
#   SWIFT_RELEASE_CACHE    where the downloaded .pkg is kept (default ~/.cache/swift-release)
#
# The swift.org macOS toolchain package (Apache-2.0, built and notarized by the
# Swift project) ships libswiftCore and the stdlib's other dylibs for every
# Darwin platform. They are the same release as the Linux host compiler, so the
# compiled modules load in that compiler and the dylibs are the ABI the guest
# was compiled against. The package is pinned by URL and SHA-256 and unpacked
# with bsdtar (xar + gzip cpio), so this runs on Linux.
#
# The dylibs are the iOS-simulator slices, retargeted to macOS like the rest
# of the base runtime root (build_full.sh retargets the root to the simulator
# for an iOS triple). The macOS arm64 slices read Darwin's thread-specific data
# inline from TPIDRRO_EL0 (two sites in libswiftCore, swift_beginAccess's TLS
# among them), which a Linux process cannot set: measured, swift_beginAccess
# faults reading 0x358. The simulator slices reach TSD through
# pthread_getspecific, have no crash backtracer, and export the macOS slices'
# symbols apart from $ld$previous markers and two Mac Catalyst variant
# availability checks. The modules are the macOS slices', for macOS-triple
# compiles.
#
# Not in the package: the Darwin SDK overlays (Darwin, _DarwinFoundation1-3,
# _errno, ObjectiveC). Apple ships those in the OS; build_sdk_overlays.sh
# builds them.
set -euo pipefail
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SWIFTCORE_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

VERSION=6.4.2
URL=https://download.swift.org/swift-$VERSION-release/xcode/swift-$VERSION-RELEASE/swift-$VERSION-RELEASE-osx.pkg
SHA256=0a7d8489900d21dbf5f0187cb570e646a4c0226d0ddef2cbde8c7f54dfe79736

OUT=${1:-$SWIFTCORE_ROOT/build/release-runtime}
CACHE=${SWIFT_RELEASE_CACHE:-$HOME/.cache/swift-release}
if [ -z "${SWIFTCORE_DARWIN_ARCH:-}" ]; then
  case "$(uname -m)" in
    aarch64|arm64) SWIFTCORE_DARWIN_ARCH=arm64 ;;
    x86_64) SWIFTCORE_DARWIN_ARCH=x86_64 ;;
    *) echo "fetch_release_runtime: unsupported host $(uname -m)" >&2; exit 2 ;;
  esac
fi
ARCH=$SWIFTCORE_DARWIN_ARCH
LIPO=${LIPO:-llvm-lipo-18}

# The artifacts set build_stdlib.sh stages (artifacts/<arch>.manifest.json),
# minus the SDK overlays the package does not carry, plus SwiftOnoneSupport,
# which -Onone code imports (the x86_64 route builds it in swift64_sysroot_extras.sh).
DYLIBS=(libswiftCore libswift_Concurrency libswift_Builtin_float libswift_RegexParser
  libswift_StringProcessing libswiftObservation libswiftSynchronization libswiftSwiftOnoneSupport)
MODULES=(Swift _Concurrency _Builtin_float _RegexParser _StringProcessing Observation Synchronization
  SwiftOnoneSupport)

for t in bsdtar "$LIPO" curl sha256sum; do
  command -v "$t" >/dev/null || { echo "fetch_release_runtime: missing $t" >&2; exit 2; }
done

pkg=$CACHE/swift-$VERSION-RELEASE-osx.pkg
mkdir -p "$CACHE"
if [ ! -f "$pkg" ] || [ "$(sha256sum "$pkg" | cut -d' ' -f1)" != "$SHA256" ]; then
  echo "fetch_release_runtime: downloading $URL"
  curl -fsSL -o "$pkg.part" "$URL"
  mv "$pkg.part" "$pkg"
fi
have=$(sha256sum "$pkg" | cut -d' ' -f1)
[ "$have" = "$SHA256" ] || { echo "fetch_release_runtime: $pkg sha256 $have, want $SHA256" >&2; exit 2; }

work=$(mktemp -d)
trap 'rm -rf -- "$work"' EXIT
(cd "$work" && bsdtar -xf "$pkg")
# bsdtar's xar reader runs the directory and member names together; find the
# one component payload by its file name.
payload=$(find "$work" -type f -name Payload)
[ "$(printf '%s\n' "$payload" | wc -l)" = 1 ] && [ -n "$payload" ] \
  || { echo "fetch_release_runtime: expected one Payload in the package, found: $payload" >&2; exit 2; }
mkdir -p "$work/root"
members=(usr/lib/swift/macosx/libswiftCore.dylib)
for d in "${DYLIBS[@]}"; do members+=("usr/lib/swift/iphonesimulator/$d.dylib"); done
for m in "${MODULES[@]}"; do members+=("usr/lib/swift/macosx/$m.swiftmodule"); done
bsdtar -xf "$payload" -C "$work/root" "${members[@]}"
src=$work/root/usr/lib/swift/macosx
sim=$work/root/usr/lib/swift/iphonesimulator

# The macOS slice's LC_BUILD_VERSION, which the retargeted dylibs take.
"$LIPO" -thin "$ARCH" "$src/libswiftCore.dylib" -output "$work/mac-core.dylib"
read -r minos sdk < <(llvm-otool-18 -l "$work/mac-core.dylib" \
  | awk '/cmd LC_BUILD_VERSION/ {b = 1} b && $1 == "minos" {m = $2} b && $1 == "sdk" {s = $2}
         b && m != "" && s != "" {print m, s; exit}')
[ -n "${minos:-}" ] && [ -n "${sdk:-}" ] \
  || { echo "fetch_release_runtime: no LC_BUILD_VERSION in the macOS libswiftCore slice" >&2; exit 2; }

rm -rf "$OUT"
mkdir -p "$OUT/swift-macosx/$ARCH"
for d in "${DYLIBS[@]}"; do
  "$LIPO" -thin "$ARCH" "$sim/$d.dylib" -output "$OUT/swift-macosx/$ARCH/$d.dylib"
  python3 -B "$SWIFTCORE_ROOT/../full/scripts/retarget_macho_build_version.py" \
    --platform 1 --minimum-os "$minos" --sdk "$sdk" "$OUT/swift-macosx/$ARCH/$d.dylib"
done
for m in "${MODULES[@]}"; do
  dest=$OUT/swift-macosx/$m.swiftmodule
  mkdir -p "$dest"
  found=0
  for f in "$src/$m.swiftmodule/$ARCH-apple-macos".*; do
    [ -e "$f" ] || continue
    cp "$f" "$dest/"
    found=1
  done
  [ "$found" = 1 ] || { echo "fetch_release_runtime: no $ARCH-apple-macos files in $m.swiftmodule" >&2; exit 2; }
done
{
  echo "swift.org $VERSION-RELEASE macOS toolchain package"
  echo "url $URL"
  echo "sha256 $SHA256"
  echo "arch $ARCH"
  (cd "$OUT" && find swift-macosx -type f | LC_ALL=C sort | xargs sha256sum)
} >"$OUT/SOURCE.txt"
echo "fetch_release_runtime: staged ${#DYLIBS[@]} dylibs and ${#MODULES[@]} modules ($ARCH) at $OUT"
