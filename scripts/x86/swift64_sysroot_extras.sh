#!/usr/bin/env bash
# Adds SwiftOnoneSupport (module + dylib), which -Onone code imports, to openuikit's x86_64
# macOS-guest sysroot; the x86_64 Swift artifacts do not include it.
set -euo pipefail
W=/home/ubuntu/openuikit
SYS=$W/scratch/sysroot_fe4-x86_64
ART=$W/swiftcore-macho/artifacts/swift-macosx
ROOT=$W/scratch/mrroot_full-x86_64/darwin/usr/lib/swift
TARGET=x86_64-apple-macos15.0
cd $W

# Swift 6.4 on a Linux host does not search <resource-dir>/shims for Darwin targets, and the Swift
# module imports the SwiftShims Clang module. Clang finds usr/include/<dir>/module.modulemap itself.
if [ ! -f $SYS/usr/include/SwiftShims/module.modulemap ]; then
    mkdir -p $SYS/usr/include/SwiftShims
    cp -a /home/ubuntu/work642/build/lib/swift/shims/. $SYS/usr/include/SwiftShims/
    echo "staged SwiftShims into the sysroot"
fi

# Only SwiftOnoneSupport is added. Copying the artifact overlay modules (_Concurrency etc.) in as
# well breaks the build: their binary modules are rejected and their interfaces do not parse.

work=$(mktemp -d /tmp/onone.XXXXXX)
curl -fsSL -o $work/SwiftOnoneSupport.swift \
    https://raw.githubusercontent.com/swiftlang/swift/swift-6.2.4-RELEASE/stdlib/public/SwiftOnoneSupport/SwiftOnoneSupport.swift
mkdir -p $SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule
# Flags from stdlib/public/SwiftOnoneSupport/CMakeLists.txt (Swift 6.2.4).
swiftc -target $TARGET -sdk $SYS -module-name SwiftOnoneSupport -parse-stdlib -parse-as-library -O -language-mode 5 \
    -Xllvm -sil-inline-generics=false -Xfrontend -validate-tbd-against-ir=none \
    -Xfrontend -check-onone-completeness -Xfrontend -disable-access-control \
    -enable-library-evolution -runtime-compatibility-version none \
    -emit-module -emit-module-path $SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftmodule \
    -emit-module-interface-path $SYS/usr/lib/swift/SwiftOnoneSupport.swiftmodule/x86_64-apple-macos.swiftinterface \
    -c -o $work/SwiftOnoneSupport.o $work/SwiftOnoneSupport.swift

# Link like swiftcore-macho/scripts/link_macho_dylib.sh: clang driver for Darwin, Ubuntu's ld64.lld-18.
clang-18 -target $TARGET -isysroot $SYS -fuse-ld=lld -B /usr/lib/llvm-18/bin \
    -dynamiclib -install_name /usr/lib/swift/libswiftSwiftOnoneSupport.dylib \
    -compatibility_version 1 -current_version 1 \
    -L$SYS/usr/lib -L$SYS/usr/lib/swift -nostdlib $work/SwiftOnoneSupport.o \
    -lSystem -lswiftCore -Wl,-undefined,dynamic_lookup \
    -o $work/libswiftSwiftOnoneSupport.dylib
cp $work/libswiftSwiftOnoneSupport.dylib $SYS/usr/lib/swift/
cp $work/libswiftSwiftOnoneSupport.dylib $ROOT/
file $ROOT/libswiftSwiftOnoneSupport.dylib
llvm-nm-18 -gU $ROOT/libswiftSwiftOnoneSupport.dylib | wc -l
[ "$(id -u)" = 0 ] && chown -R ubuntu:ubuntu $SYS $ROOT || true
