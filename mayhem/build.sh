#!/usr/bin/env bash
# Catch2 — cmake fuzz harnesses (upstream fuzzing/) + SelfTest oracle build.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

FUZZ_FLAGS="$SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link"

# 1) Sanitized Catch2 + libFuzzer harnesses (upstream fuzzing/CMakeLists.txt).
cmake -S . -B build-fuzz \
  -DCMAKE_C_COMPILER="$CC" \
  -DCMAKE_CXX_COMPILER="$CXX" \
  -DCMAKE_C_FLAGS="$FUZZ_FLAGS" \
  -DCMAKE_CXX_FLAGS="$FUZZ_FLAGS" \
  -DCATCH_DEVELOPMENT_BUILD=ON \
  -DCATCH_BUILD_FUZZERS=ON \
  -DCATCH_BUILD_TESTING=OFF \
  -DCATCH_BUILD_EXAMPLES=OFF \
  -DCATCH_BUILD_EXTRA_TESTS=OFF \
  -DCATCH_ENABLE_WERROR=OFF \
  -DBUILD_TESTING=OFF

cmake --build build-fuzz -j"$MAYHEM_JOBS" \
  --target fuzz_TestSpecParser fuzz_XmlWriter fuzz_textflow

install -m 0755 build-fuzz/fuzzing/fuzz_TestSpecParser /mayhem/fuzz_TestSpecParser
install -m 0755 build-fuzz/fuzzing/fuzz_XmlWriter     /mayhem/fuzz_XmlWriter
install -m 0755 build-fuzz/fuzzing/fuzz_textflow      /mayhem/fuzz_textflow

# 2) Standalone (non-libFuzzer) reproducers — C++ harnesses need the driver as a C object.
LIB_CATCH2="$(find build-fuzz -name 'libCatch2.a' | head -1)"
GEN_INCLUDES="build-fuzz/generated-includes"
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o /tmp/standalone_main.o

for name in TestSpecParser XmlWriter textflow; do
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -std=c++17 \
    "$SRC/fuzzing/fuzz_${name}.cpp" \
    "$SRC/fuzzing/NullOStream.cpp" \
    -I"$SRC/src" \
    -I"$GEN_INCLUDES" \
    /tmp/standalone_main.o \
    "$LIB_CATCH2" \
    -o "/mayhem/fuzz_${name}-standalone"
done

# 3) SelfTest suite (normal flags) for mayhem/test.sh — oracle must not compile here.
cmake -S . -B build-tests \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_FLAGS="$COVERAGE_FLAGS" \
  -DCMAKE_CXX_FLAGS="$COVERAGE_FLAGS" \
  -DCATCH_DEVELOPMENT_BUILD=ON \
  -DCATCH_BUILD_TESTING=ON \
  -DCATCH_BUILD_FUZZERS=OFF \
  -DCATCH_BUILD_EXAMPLES=OFF \
  -DCATCH_BUILD_EXTRA_TESTS=OFF \
  -DCATCH_ENABLE_WERROR=OFF \
  -DCATCH_ENABLE_CONFIGURE_TESTS=OFF \
  -DBUILD_TESTING=ON

cmake --build build-tests -j"$MAYHEM_JOBS" --target SelfTest
