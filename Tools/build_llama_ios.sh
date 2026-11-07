#!/bin/sh
# Builds llama.cpp (the Vendor/llama.cpp submodule) as CPU-only static
# libraries for iOS devices and the simulator into Vendor/llama-cpu (not in
# git). Metal is left out on purpose: its startup alone uses ~45 MB, more
# than half of a keyboard extension's ~76 MB memory limit.
# Needs cmake and ninja (brew install cmake ninja).
# usage: Tools/build_llama_ios.sh
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="$ROOT/Vendor/llama.cpp"; OUT="$ROOT/Vendor/llama-cpu"
[ -f "$SRC/include/llama.h" ] || git -C "$ROOT" submodule update --init --depth 1 Vendor/llama.cpp
for target in iphoneos iphonesimulator; do
  BUILD="$ROOT/build/llama-$target"   # outside the submodule, so it stays clean
  cmake -S "$SRC" -B "$BUILD" -G Ninja -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT=$target -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=16.4 -DBUILD_SHARED_LIBS=OFF \
    -DGGML_METAL=OFF -DGGML_BLAS=OFF -DGGML_NATIVE=OFF -DGGML_OPENMP=OFF \
    -DLLAMA_CURL=OFF -DLLAMA_BUILD_COMMON=OFF -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_EXAMPLES=OFF -DLLAMA_BUILD_TOOLS=OFF -DLLAMA_BUILD_SERVER=OFF
  cmake --build "$BUILD" --target llama
  mkdir -p "$OUT/lib/$target"
  cp "$BUILD/src/libllama.a" "$BUILD"/ggml/src/libggml*.a "$OUT/lib/$target/"
done
mkdir -p "$OUT/include"
cp "$SRC/include/llama.h" "$SRC"/ggml/include/*.h "$OUT/include/"
cp "$ROOT/Tools/llama/module.modulemap" "$OUT/include/"
cp "$SRC/LICENSE" "$OUT/"
echo "done: $OUT"
