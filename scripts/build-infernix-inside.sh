#!/usr/bin/env bash
# Build Infernix inside the CUDA container and package infernix + infernix-serve.
#
# Infernix is not a llama.cpp fork: its CMake options are INFERNIX_* and its
# Dockerfile builds on CUDA 13.1. This lane builds with the lane's own CUDA_TAG
# (13.2 — forward compatible with what its Dockerfile used, per our image base)
# and mirrors their documented target list. Env: REPO/IMP-alias, REF, SUBDIR,
# MODE, CUDA_TAG.
set -e

# Same malformed-index workaround as the imp lane (de mirrors, drop cuda apt list).
sed -i 's|archive.ubuntu.com|de.archive.ubuntu.com|g; s|security.ubuntu.com|de.archive.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
rm -f /etc/apt/sources.list.d/cuda*.list

apt-get update -qq
# Infernix Dockerfile build-stage list (Dockerfile:6-14): cmake, ffmpeg dev libs,
# curl dev, ninja, pkg-config. cmake from apt (fork lanes precedent).
apt-get install -y --no-install-recommends \
    cmake ninja-build pkg-config git ccache \
    libavcodec-dev libavformat-dev libavutil-dev libswscale-dev \
    libcurl4-openssl-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

missing=""
for t in git cmake ninja ccache strip objdump pkg-config; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then echo "FATAL: missing tools:$missing" >&2; exit 1; fi

ccache -M 3G
ccache -z

cd /workspace
git clone "https://github.com/${INFERnix_REPO:-$REPO}.git" src
cd src
git checkout "$REF"

cmake -B build -S . \
  -G Ninja \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
  -DCMAKE_BUILD_TYPE=Release \
  -DINFERNIX_BUILD_APPS=ON \
  -DBUILD_TESTING=OFF \
  -DINFERNIX_BUILD_BENCHMARKS=OFF

# Runner RAM budget: Infernix is a single CUDA binary; -j$(nproc) is safe on
# 16 GB runners (no CUTLASS fan-out like imp). Trim to 4 if OOM resurfaces.
cmake --build build --config Release -j"$(nproc)" --target infernix infernix-serve

echo '=== CCache Statistics ==='
ccache -s

cd /workspace
mkdir -p "binaries/${SUBDIR}"
for b in infernix infernix-serve; do
  [ -x "src/build/apps/$b" ] && cp -a "src/build/apps/$b" "binaries/${SUBDIR}/" || \
    { echo "MISSING: src/build/apps/$b" >&2; exit 1; }
done
find "binaries/${SUBDIR}/" -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

{
  echo "engine: ${REPO}"
  echo "mode: ${MODE:-nightly}"
  echo "ref: ${REF}"
  echo "CUDA version: ${CUDA_TAG}"
  echo "Build date: $(date -u +%Y-%m-%d)"
} > "binaries/${SUBDIR}/VERSION.txt"

# Sanity: server binary must link libcudart.so.13 (CUDA-12 build would fail the
# swap image at exec, and nvidia-smi inside would pass the same trap).
SONAME=$(objdump -p "binaries/${SUBDIR}/infernix-serve" | awk '/NEEDED/ {print $2}' | grep -c 'libcudart\.so\.13' || true)
[ "${SONAME}" -gt 0 ] || { echo "FATAL: infernix-serve does not link libcudart.so.13" >&2; ldd "binaries/${SUBDIR}/infernix-serve" | head >&2; exit 1; }
ldd "binaries/${SUBDIR}/infernix-serve" | awk '/not found/ {print "FATAL unresolved:", $1; exit 1}'
echo "infernix-serve links libcudart.so.13 - OK"
ls -lh "binaries/${SUBDIR}/"
