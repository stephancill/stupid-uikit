#!/usr/bin/env bash
# stage_ios_sim_sysroot.sh -- the x86_64 iOS-simulator compile sysroot, beside
# the macOS one: scratch/sysroot_fe4-x86_64-iossim (SYS for
# TARGET=x86_64-apple-ios<ver>-simulator, see full/scripts/guest_arch.inc) plus
# scratch/apple-overlays-x86_64-iossim (APPLE_SWIFT_USER_OVERLAYS).
#
#   IOS_SDK=<dir> W=<tree> bash scripts/x86/stage_ios_sim_sysroot.sh
#
# IOS_SDK is a local copy of the parts of an iPhoneSimulator SDK this route
# reads (Xcode 27's: usr/lib/swift/*.swiftmodule/x86_64-apple-ios-simulator.*,
# usr/lib/swift/*.tbd, usr/lib/{libSystem.B,libobjc.A}.tbd, SDKSettings.json),
# copied from a Mac with:
#   cd "$(xcrun --sdk iphonesimulator --show-sdk-path)" && tar czf sub.tgz \
#     usr/lib/swift/*.swiftmodule/x86_64-apple-ios-simulator.swift{interface,doc} \
#     usr/lib/swift/*.tbd usr/lib/libSystem.B.tbd usr/lib/libobjc.A.tbd SDKSettings.json
# Apple SDK files stay local to the build host: never commit or publish them.
#
# Built over the x86_64 macOS sysroot (scripts/x86/stage_fe_sysroot.sh) by the
# arm64 route's stager (full/xcodeplan/stage_true_ios_full_sdk.sh): Apple's
# iOS-simulator stdlib interfaces in the SDK, the Darwin/ObjectiveC overlays as
# -I modules. Then, as full/iostarget/ios_guest.sh does for libSystem/libobjc,
# every .tbd the macOS sysroot generated from the guest's real dylibs replaces
# Apple's and is retargeted to x86_64-ios-simulator: the guest runs the
# open-source 6.4.2 runtime under machorun, so the link must bind to what that
# runtime exports (a symbol only Apple's libswiftCore has fails at link time,
# not at load). Apple .tbds stay only where the guest has no dylib at all.
set -euo pipefail
W=${W:?set W to the openuikit tree}
IOS_SDK=${IOS_SDK:?set IOS_SDK to the staged iPhoneSimulator SDK subset}
# The guest architecture is the host's (an aarch64 host stages the arm64 slices).
case "${ARCH:-$(uname -m)}" in
    x86_64) ARCH=x86_64 ;;
    aarch64 | arm64) ARCH=arm64 ;;
    *) echo "stage_ios_sim_sysroot: unsupported architecture ${ARCH:-$(uname -m)}" >&2; exit 2 ;;
esac
MAC_SYS=${MAC_SYS:-$W/scratch/sysroot_fe4-$ARCH}
OUT_SYS=${OUT_SYS:-$W/scratch/sysroot_fe4-$ARCH-iossim}
OUT_OVERLAYS=${OUT_OVERLAYS:-$W/scratch/apple-overlays-$ARCH-iossim}
die() { echo "stage_ios_sim_sysroot: $*" >&2; exit 2; }

[ -d "$MAC_SYS/usr/lib/swift" ] || die "no $ARCH macOS sysroot at $MAC_SYS (scripts/x86/stage_fe_sysroot.sh)"
[ -f "$IOS_SDK/usr/lib/swift/Swift.swiftmodule/$ARCH-apple-ios-simulator.swiftinterface" ] \
    || die "IOS_SDK has no $ARCH iOS-simulator Swift interface: $IOS_SDK"

work=$(mktemp -d "$W/scratch/.ios-sim-sysroot.XXXXXX")
trap 'rm -rf -- "$work"' EXIT
mkdir -p "$work/core"
ln -s "$MAC_SYS" "$work/core/sdk"
STAGE_TRUE_IOS_ARCH=$ARCH bash "$W/full/xcodeplan/stage_true_ios_full_sdk.sh" \
    "$work/core" "$IOS_SDK" "$work/out"

# The guest's own runtime, not Apple's (header): retarget the macOS sysroot's
# generated .tbds over the Apple copies.
replaced=0
while IFS= read -r -d '' tbd; do
    rel=${tbd#"$MAC_SYS/"}
    grep -q "$ARCH-macos" "$tbd" || die "$rel is not an $ARCH-macos .tbd"
    rm -f "$work/out/sdk/$rel"
    sed "s/$ARCH-macos/$ARCH-ios-simulator/g" "$tbd" > "$work/out/sdk/$rel"
    replaced=$((replaced + 1))
done < <(find "$MAC_SYS/usr/lib" -name '*.tbd' -type f -print0)
apple_only=()
while IFS= read -r -d '' tbd; do
    rel=${tbd#"$work/out/sdk/"}
    [ -f "$MAC_SYS/$rel" ] || apple_only+=("$rel")
done < <(find "$work/out/sdk/usr/lib" -name '*.tbd' -type f -print0)
# Swift itself compiles against Apple's iOS-simulator interface, as on arm64.
# The guest's source-built macOS interface cannot stand in: it was emitted for
# macOS x86_64, which has no Float16, and Apple's Synchronization interface
# needs Float16 on the iOS simulator (MEASURED: "value of type 'Float16' has no
# member 'bitPattern'" building Synchronization for FoundationEssentials).
leftover=$(grep -l "$ARCH-macos" -r "$work/out/sdk/usr/lib" --include='*.tbd' || true)
[ -z "$leftover" ] || die "macOS .tbd left in the iOS sysroot: $leftover"

rm -rf -- "$OUT_SYS" "$OUT_OVERLAYS"
mv "$work/out/sdk" "$OUT_SYS"
mv "$work/out/apple-overlays" "$OUT_OVERLAYS"
cp "$work/out/attestation/target-sdk-inputs.sha256" "$OUT_SYS/.ios-sim-sdk-inputs.sha256"
echo "stage_ios_sim_sysroot: $OUT_SYS ($replaced guest .tbds retargeted; Apple-only: ${apple_only[*]:-none})"
echo "stage_ios_sim_sysroot: overlays $OUT_OVERLAYS"
