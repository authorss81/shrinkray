#!/usr/bin/env bash
# =============================================================================
# build-engine.sh — compile the PixelSmith Rust engine for the current target
# and place the library where Flutter expects it.
#
# Usage:
#   bash native/build-engine.sh [--release] [--engine-dir PATH]
#
# --engine-dir defaults to ../pixelsmith (a checkout next to this repository),
# which is the layout when shrinkray is pulled in as the `app/` submodule of
# pixelsmith. In CI the workflow clones the engine explicitly and passes
# --engine-dir; see .github/workflows/build.yml.
#
# Outputs, by platform:
#   Android:  src/rust/jniLibs/<abi>/libpixelsmith_core.so  (via cargo-ndk)
#   iOS:      linked statically via cargo-lipo (see ios/ build phase)
#   Windows:  src/rust/pixelsmith_core.dll, next to the EXE at packaging time
#   Linux:    src/rust/libpixelsmith_core.so
#   macOS:    src/rust/libpixelsmith_core.dylib
# =============================================================================

set -euo pipefail

RELEASE=0
ENGINE_DIR=""
while [ $# -gt 0 ]; do
  case "$1" in
    --release) RELEASE=1; shift ;;
    --engine-dir) ENGINE_DIR="$2"; shift 2 ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
done

if [ -z "${ENGINE_DIR}" ]; then
  if [ -d "../pixelsmith/core" ]; then
    ENGINE_DIR="../pixelsmith"
  elif [ -d "../core" ]; then
    ENGINE_DIR=".."
  else
    echo "error: no engine found. Pass --engine-dir <pixelsmith checkout>." >&2
    echo "hint: git clone https://github.com/authorss81/pixelsmith.git" >&2
    exit 2
  fi
fi

if [ ! -f "${ENGINE_DIR}/core/Cargo.toml" ]; then
  echo "error: ${ENGINE_DIR}/core/Cargo.toml not found." >&2
  exit 2
fi

CARGO_ARGS=(build --lib)
if [ "${RELEASE}" = "1" ]; then CARGO_ARGS+=(--release); fi

OS="$(uname -s)"
case "${OS}" in
  Linux)
    if [ -n "${ANDROID_NDK_HOME:-}" ]; then
      # Cross-compiling for Android from a Linux host. cargo-ndk supplies the
      # NDK clang wrapper that plain `cargo build --target` lacks, which is
      # what failed the first engine-matrix run with a linker error.
      command -v cargo-ndk >/dev/null 2>&1 || cargo install cargo-ndk
      mkdir -p src/rust/jniLibs
      ( cd "${ENGINE_DIR}/core" && cargo ndk -t arm64-v8a -t x86_64 \
          -o "${OLDPWD}/src/rust/jniLibs" "${CARGO_ARGS[@]}" )
      echo "android: src/rust/jniLibs"
      find src/rust/jniLibs -name '*.so'
    else
      mkdir -p src/rust
      ( cd "${ENGINE_DIR}/core" && cargo "${CARGO_ARGS[@]}" )
      cp "${ENGINE_DIR}/core/target/$([ "${RELEASE}" = "1" ] && echo release || echo debug)/libpixelsmith_core.so" src/rust/
      echo "linux: src/rust/libpixelsmith_core.so"
    fi
    ;;
  Darwin)
    mkdir -p src/rust
    ( cd "${ENGINE_DIR}/core" && cargo "${CARGO_ARGS[@]}" )
    cp "${ENGINE_DIR}/core/target/$([ "${RELEASE}" = "1" ] && echo release || echo debug)/libpixelsmith_core.dylib" src/rust/
    echo "macos: src/rust/libpixelsmith_core.dylib"
    ;;
  MINGW*|MSYS*|CYGWIN*)
    mkdir -p src/rust
    ( cd "${ENGINE_DIR}/core" && cargo "${CARGO_ARGS[@]}" )
    profile=debug; [ "${RELEASE}" = "1" ] && profile=release
    cp "${ENGINE_DIR}/core/target/${profile}/pixelsmith_core.dll" src/rust/
    echo "windows: src/rust/pixelsmith_core.dll"
    ;;
  *)
    echo "error: unsupported host ${OS}. Build the engine manually and place it in src/rust/." >&2
    exit 2
    ;;
esac
