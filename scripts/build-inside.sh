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
  -DBUILD_SHARED_LIBS=ON \
  -DGGML_NATIVE=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_UI=OFF \
  -DLLAMA_USE_PREBUILT_UI=OFF \
  -DLLAMA_BUILD_WEBUI=OFF \
  -DCMAKE_EXE_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs' \
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

# Bundle CUDA runtime so users don't need the full toolkit installed
CUDA_LIB=/usr/local/cuda/targets/x86_64-linux/lib
cp -a "${CUDA_LIB}"/libcudart.so* "binaries/${SUBDIR}/"
cp -a "${CUDA_LIB}"/libcublas.so* "binaries/${SUBDIR}/"
cp -a "${CUDA_LIB}"/libcublasLt.so* "binaries/${SUBDIR}/"

find "binaries/${SUBDIR}/" -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

echo "fork: ${REPO} (${BRANCH:-release})" > "binaries/${SUBDIR}/VERSION.txt"
echo "mode: ${MODE}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "ref: ${REF}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "release-tag: ${RELTAG}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "CUDA version: 13.2.0" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Architectures: ${ARCHS}" >> "binaries/${SUBDIR}/VERSION.txt"
echo "Build date: $(date -u +%Y-%m-%d)" >> "binaries/${SUBDIR}/VERSION.txt"

ls -lh "binaries/${SUBDIR}/"
rm -rf src
