#!/bin/bash
set -Eeuxo pipefail

### Determine build configuration

EH=${EH:-OFF}
if [ "$EH" != "ON" ]; then EH=OFF ; fi
PIC=${PIC:-OFF}
if [ "$PIC" != "ON" ]; then PIC=OFF ; fi
EXNREF_EH=${EXNREF_EH:-ON}
if [ "$EXNREF_EH" != "OFF" ]; then EXNREF_EH=ON ; fi

REPO_ROOT="$(pwd)"

case "${EH}-${PIC}-${EXNREF_EH}" in
    ON-ON-ON)   NAME="32-exnref-ehpic" ;;
    ON-OFF-ON)  NAME="32-exnref-eh" ;;
    ON-ON-OFF)   NAME="32-ehpic" ;;
    ON-OFF-OFF)  NAME="32-eh" ;;
    OFF-ON-*)  echo "PIC is only supported when exception handling is enabled" ; exit 1 ;;
    OFF-OFF-ON)  NAME="32" ;;
    *)       echo "Invalid EH/PIC/EXNREF_EH combination: EH:${EH} PIC:${PIC} EXNREF_EH:${EXNREF_EH}" ; exit 1 ;;
esac

if [ "$EH" = "ON" ]; then
    CMAKE_TOOLCHAIN="$REPO_ROOT"/tools/clang-wasix-exnref-eh.cmake_toolchain
    if [ "$EXNREF_EH" = "OFF" ]; then
        CMAKE_TOOLCHAIN="$REPO_ROOT"/tools/clang-wasix-eh.cmake_toolchain
    fi
else
    CMAKE_TOOLCHAIN="$REPO_ROOT"/tools/clang-wasix.cmake_toolchain
fi

### Path names of various build artifacts

wasix_libc_output="build/wasix-libc-sysroot-$NAME"

compiler_rt_build_dir="build/compiler-rt-$NAME"
compiler_rt_output="build/compiler-rt-sysroot-$NAME"
compiler_rt_build_sysroot="build/compiler-rt-build-sysroot-$NAME"

libcxx_build_dir="build/libcxx-$NAME"
libcxx_output="build/libcxx-sysroot-$NAME"
libcxx_build_sysroot="build/libcxx-build-sysroot-$NAME"

sysroot_output="sysroot$NAME"

### Build settings

export TARGET_ARCH=wasm32
export TARGET_OS=wasix


### Build steps

# Regenerate bindings in libc-bottom-half
prepare_wasix_libc() {
    # Build the extensions
    cargo run --manifest-path tools/wasix-headers/Cargo.toml generate-libc
    cp -f libc-bottom-half/headers/public/wasi/api.h libc-bottom-half/headers/public/wasi/api_wasix.h
    sed -i 's|__wasi__|__wasix__|g' libc-bottom-half/headers/public/wasi/api_wasix.h
    sed -i 's|__wasi_api_h|__wasix_api_h|g' libc-bottom-half/headers/public/wasi/api_wasix.h
    cp -f libc-bottom-half/sources/__wasilibc_real.c libc-bottom-half/sources/__wasixlibc_real.c
    
    # Build WASI
    cargo run --manifest-path tools/wasi-headers/Cargo.toml generate-libc
    cp -f libc-bottom-half/headers/public/wasi/api.h libc-bottom-half/headers/public/wasi/api_wasi.h
    
    # Emit the API header
    cat > libc-bottom-half/headers/public/wasi/api.h<<EOF
#include "api_wasi.h"
#include "api_wasix.h"
#include "api_poly.h"
EOF
}

# Build wasix-libc
wasix_libc() {
    MAKEFLAGS=""
    if [ "$PIC" = "ON" ]; then
        MAKEFLAGS="$MAKEFLAGS PIC=yes"
    else
        MAKEFLAGS="$MAKEFLAGS PIC=no"
    fi
    if [ "$EH" = "ON" ]; then
        MAKEFLAGS="$MAKEFLAGS EH=yes"
        if [ "$EXNREF_EH" = "ON" ]; then
            MAKEFLAGS="$MAKEFLAGS EXNREF_EH=yes"
        else
            MAKEFLAGS="$MAKEFLAGS EXNREF_EH=no"
        fi
    else
        MAKEFLAGS="$MAKEFLAGS EH=no"
    fi

    # Cleanup previous build artifacts
    rm -rf sysroot
    rm -rf build/wasm32-wasi
    rm -rf $wasix_libc_output

    # shellcheck disable=SC2086
    CC=clang CXX=clang++ make CHECK_SYMBOLS="${CHECK_SYMBOLS:-yes}" -j 16 $MAKEFLAGS
    rm -f sysroot/lib/wasm32-wasi/libc-printscan-long-double.a
    rm -rf $wasix_libc_output
    mv sysroot $wasix_libc_output
}

sysroot() {
    rm -rf $sysroot_output
    mkdir -p $sysroot_output
    rsync -abuz  $wasix_libc_output/ $sysroot_output/
}

### Run build steps

# Generate files in wasix-libc
prepare_wasix_libc
# Build wasix-libc
wasix_libc
# Build the sysroot
sysroot
