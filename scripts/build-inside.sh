#!/usr/bin/env bash
# Build llama.cpp fork inside the CUDA container and package the 3 primary
# binaries (llama-server, llama-cli, llama-bench). For the vanilla fork only,
# also package the CUDA runtime libs into a separate asset (see below).
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
# CUDA runtime .so's (cudart/cublas/cublasLt) are NOT bundled in the fork
# tarball: the swap image is FROM nvidia/cuda:13.2-runtime, which already
# provides them at /usr/local/cuda/lib64 (CUDA ABI is stable within a major
# version, so a binary built against 13.2-devel runs fine against 13.2-runtime).
# For local, non-Docker use the vanilla release ships them separately below.

find "binaries/${SUBDIR}/" -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

# Only the vanilla build ships the shared CUDA runtime asset. It is written to
# a SEPARATE directory (cuda-asset/, NOT binaries/) so it never pollutes the
# per-fork tarball glob used by upload/publish, and so the other forks stay
# light. The swap image does NOT need this (its base nvidia/cuda:runtime
# already provides the CUDA .so's).
if [ "$SUBDIR" = "vanilla" ]; then
  # Asset name uses major.minor (13.2) to match the documented filename
  # cuda-runtime-13.2-amd64.tar.gz (forks.json cuda_version_short).
  CUDA_VER=$(echo "${CUDA_TAG:-13.2.0-cudnn-devel-ubuntu24.04}" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')
  # The CUDA runtime .so's live in different dirs across toolkit images
  # (/usr/local/cuda/lib64 vs /usr/local/cuda/targets/x86_64-linux/lib).
  # Probe both and use whichever actually has them.
  CUDA_LIB=""
  for d in /usr/local/cuda/lib64 /usr/local/cuda/targets/x86_64-linux/lib; do
    if ls "$d"/libcudart.so* >/dev/null 2>&1; then CUDA_LIB="$d"; break; fi
  done
  [ -n "$CUDA_LIB" ] || { echo "CUDA runtime libs not found"; exit 1; }
  mkdir -p /workspace/cuda-asset
  CUDA_TARBALL="/workspace/cuda-asset/cuda-runtime-${CUDA_VER}-amd64.tar.gz"
  tmp_cuda=$(mktemp -d)
  # -L dereferences symlinks: in the toolkit image lib64 holds symlinks
  # (libcudart.so -> ... -> real file in targets/), so a plain cp would copy
  # dangling links. -L copies the real library bytes, making the asset
  # self-contained for local (non-Docker) use.
  for lib in libcudart.so* libcublas.so* libcublasLt.so*; do
    cp -L "${CUDA_LIB}/$lib" "$tmp_cuda/" 2>/dev/null || true
  done
  # strip the CUDA libs too — shrinks the asset considerably
  find "$tmp_cuda" -type f -executable -exec strip {} \; 2>/dev/null || true
  tar -czf "$CUDA_TARBALL" -C "$tmp_cuda" .
  rm -rf "$tmp_cuda"
  echo "created $CUDA_TARBALL ($(du -h "$CUDA_TARBALL" | cut -f1))"
fi

echo "fork: ${REPO} (${BRANCH:-release})" > "binaries/${SUBDIR}/VERSION.txt"
echo "mode: ${MODE}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "ref: ${REF}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "release-tag: ${RELTAG}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "CUDA version: 13.2.0" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Architectures: ${ARCHS}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Build date: $(date -u +%Y-%m-%d)" >> "binaries/${SUBDIR}/VERSION.txt"

# Sanity check: the three primary binaries must have been built and linked.
for b in llama-server llama-cli llama-bench; do
  [ -x "binaries/${SUBDIR}/$b" ] || { echo "MISSING: $b"; exit 1; }
done

ls -lh "binaries/${SUBDIR}/"
rm -rf src
