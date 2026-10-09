#!/usr/bin/env bash
# Build imp inside the CUDA container and package imp-server + imp-cli.
#
# Separate from build-inside.sh because imp is not a llama.cpp fork: its CMake
# options are IMP_*, not LLAMA_*, and it needs CUDA 13.4 where this repo builds
# 13.2 for the forks. Env: IMP_REPO, REF, SUBDIR, MODE, ARCHS, CUDA_TAG.
set -e

apt-get update -qq
# wget comes from the base image, not from apt's suggestion set, but the base
# variant differs between toolkit tags - install it explicitly.
apt-get install -y --no-install-recommends git ninja-build build-essential \
    libssl-dev ca-certificates ccache lld wget
apt-get clean
rm -rf /var/lib/apt/lists/*

# imp needs CMake 4.x (C++23 + CUDA 13); the distro package on this base is 3.x.
# Pinned by digest exactly like the imp PLE CI does, so both lanes build with the
# same cmake.
CMAKE_SH=/tmp/cmake.sh
wget -qO "$CMAKE_SH" https://github.com/Kitware/CMake/releases/download/v4.3.5/cmake-4.3.5-linux-x86_64.sh
echo 'b48d919cf4dec27e594f9e0c227e48274e20238bcda8b4b471a94f9099cccd83  /tmp/cmake.sh' | sha256sum -c -
sh "$CMAKE_SH" --skip-license --prefix=/usr/local
cmake --version

# Preflight: a missing tool otherwise surfaces five minutes into a container run.
missing=""
for t in git cmake ninja ccache strip objdump wget; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then
  echo "FATAL: missing tools:$missing" >&2
  exit 1
fi

ccache -M 3G
ccache -z

cd /workspace


git clone "https://github.com/${IMP_REPO}.git" src
cd src
git checkout "$REF"

ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1

cmake -B build -S . \
  -G Ninja \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
  -DCMAKE_BUILD_TYPE=Release \
  -DIMP_BUILD_TESTS=ON \
  -DIMP_BUILD_TOOLS=ON \
  -DIMP_BUILD_SERVER=ON \
  -DIMP_DISABLE_120F_FALLBACK=ON \
  -DIMP_BUILD_BENCH=OFF \
  -DCMAKE_EXE_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs -Wl,-rpath,$ORIGIN' \
  -DCMAKE_SHARED_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs'

cmake --build build --config Release -j"$(nproc)"

echo '=== CCache Statistics ==='
ccache -s

cd /workspace
mkdir -p "binaries/${SUBDIR}"
for b in imp-server imp-cli; do
  if [ -x "src/build/$b" ]; then
    cp -a "src/build/$b" "binaries/${SUBDIR}/"
  fi
done

# Binary-only: no test binaries and no sources.
find "binaries/${SUBDIR}/" -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

{
  echo "imp: ${IMP_REPO}"
  echo "mode: ${MODE:-nightly}"
  echo "ref: ${REF}"
  echo "CUDA version: ${CUDA_TAG:-13.4.2-devel-ubuntu26.04}"
  echo "Build date: $(date -u +%Y-%m-%d)"
} > "binaries/${SUBDIR}/VERSION.txt"

# Sanity check: both binaries must exist, and the server must be dynamically
# linked against libcudart.so.13 - a CUDA-12 build would fail the image, which
# is FROM nvidia/cuda:13.2-runtime.
for b in imp-server imp-cli; do
  [ -x "binaries/${SUBDIR}/$b" ] || { echo "MISSING: $b" >&2; exit 1; }
done

SONAME=$(objdump -p "binaries/${SUBDIR}/imp-server" 2>/dev/null | awk '/NEEDED/ {print $2}' | grep -c 'libcudart\.so\.13$' || true)
if [ "${SONAME}" -eq 0 ]; then
  echo "FATAL: imp-server does not link libcudart.so.13 (CUDA 13)" >&2
  ldd "binaries/${SUBDIR}/imp-server" 2>&1 | head -10 >&2
  exit 1
fi
echo "imp-server links libcudart.so.13 - OK"

ls -lh "binaries/${SUBDIR}/"
rm -rf src