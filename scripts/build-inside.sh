#!/usr/bin/env bash
# Build llama.cpp fork inside the CUDA container and package the 3 primary
# binaries (llama-server, llama-cli, llama-bench) + CUDA runtime libs.
set -e

apt-get update -qq
apt-get install -y --no-install-recommends git cmake ninja-build build-essential libssl-dev ca-certificates ccache lld
apt-get clean
rm -rf /var/lib/apt/lists/*

ccache -M 3G
ccache -z

cd /workspace

if [ -n "$BRANCH" ]; then
  git clone --branch "$BRANCH" "https://github.com/${REPO}.git" src
  cd src && git checkout "$REF" && cd ..
else
  git clone "https://github.com/${REPO}.git" src
  cd src && git checkout "$REF" && cd ..
fi
cd src

ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

cmake -B build -S . \
  -G Ninja \
  -DGGML_CUDA=ON \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CUDA_ARCHITECTURES="$ARCHS" \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=OFF \
  -DLLAMA_BUILD_WEBUI=OFF \
  -DCMAKE_EXE_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs -Wl,-rpath,$ORIGIN' \
  -DCMAKE_SHARED_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs'

cmake --build build --config Release -j"$(nproc)"

echo '=== CCache Statistics ==='
ccache -s

cd /workspace
mkdir -p "binaries/${SUBDIR}"
for b in llama-server llama-cli llama-bench; do
  if [ -x "src/build/bin/$b" ]; then
    cp -a "src/build/bin/$b" "binaries/${SUBDIR}/"
  fi
done

# llama.cpp is built with BUILD_SHARED_LIBS=OFF, so libllama/libggml are
# linked statically into each binary — no llama.cpp .so to ship.
# CUDA runtime .so's (cudart/cublas/cublasLt) are NOT bundled: the swap image
# is FROM nvidia/cuda:13.2-runtime, which already provides them at
# /usr/local/cuda/lib64 (CUDA ABI is stable within a major version, so a
# binary built against 13.2-devel runs fine against 13.2-runtime). This keeps
# the tarball ~150MB instead of ~1GB.

find "binaries/${SUBDIR}/" -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

echo "fork: ${REPO} (${BRANCH:-release})" > "binaries/${SUBDIR}/VERSION.txt"
echo "mode: ${MODE}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "ref: ${REF}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "release-tag: ${RELTAG}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "CUDA version: 13.2.0" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Architectures: ${ARCHS}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Build date: $(date -u +%Y-%m-%d)" >> "binaries/${SUBDIR}/VERSION.txt"

# Smoke test: every binary must actually start and print --help. Catches
# missing/broken shared libs (e.g. a binary that won't load at runtime)
# before we ship it. Fail the build if any binary can't run.
echo "=== smoke test (--help) ==="
for b in llama-server llama-cli llama-bench; do
  bin="binaries/${SUBDIR}/$b"
  [ -x "$bin" ] || { echo "MISSING: $b"; exit 1; }
  "$bin" --help >/dev/null 2>&1 || { echo "SMOKE FAIL: $b --help exited non-zero"; exit 1; }
  echo "ok: $b"
done

# Capture --help output per binary for the release notes (fork features are
# only discoverable from --help, so we attach it as a collapsible section).
HELP="binaries/${SUBDIR}/HELP.txt"
: > "$HELP"
for b in llama-server llama-cli llama-bench; do
  bin="binaries/${SUBDIR}/$b"
  echo "### $b --help" >> "$HELP"
  echo '```' >> "$HELP"
  "$bin" --help >> "$HELP" 2>&1 || echo "(--help failed)" >> "$HELP"
  echo '```' >> "$HELP"
  echo >> "$HELP"
done

ls -lh "binaries/${SUBDIR}/"
rm -rf src
