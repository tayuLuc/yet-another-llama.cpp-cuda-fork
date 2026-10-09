#!/usr/bin/env bash
# Build imp inside the CUDA container and package imp-server + imp-cli.
#
# Separate from build-inside.sh because imp is not a llama.cpp fork: its CMake
# options are IMP_*, not LLAMA_*, and it needs CUDA 13.4 where this repo builds
# 13.2 for the forks. Env: IMP_REPO, REF, SUBDIR, MODE, CUDA_TAG.
#
# No linker flags and no libcuda stub symlink: imp links CUDA::cuda_driver but
# the imp CI builds in the same toolkit image with neither, and copying them from
# the fork lane cost a "cannot find 'ld'" because -fuse-ld=lld needs the lld
# package that imp does not install.
set -e

# The Ubuntu index shipped malformed on 2026-09-16 (sections without a
# "Package:" header) and made apt-get update fail; the imp Dockerfile pins the
# mirror for the same reason. Kept because this is the same base image family.
sed -i 's|archive.ubuntu.com|de.archive.ubuntu.com|g; s|security.ubuntu.com|de.archive.ubuntu.com|g' \
    /etc/apt/sources.list.d/ubuntu.sources 2>/dev/null || true
rm -f /etc/apt/sources.list.d/cuda*.list

apt-get update -qq
# imp's own Dockerfile list, minus the Kitware cmake it installs separately:
# find_package() needs CURL, OpenSSL and JPEG, python3 drives FetchContent, and
# liburing-dev is what compiles the io_uring backend in - without it the shipped
# binary silently loses that backend. cmake comes from apt here: imp asks for
# 3.25 (CMakeLists.txt:1) and the fork lanes already build on the distro package.
apt-get install -y --no-install-recommends \
    cmake g++ git ninja-build ca-certificates python3 ccache \
    libcurl4-openssl-dev libjpeg-turbo8-dev liburing-dev
apt-get clean
rm -rf /var/lib/apt/lists/*

# Preflight: a missing tool otherwise surfaces five minutes into a container run.
missing=""
for t in git cmake ninja ccache strip objdump python3; do
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
  -DIMP_BUILD_BENCH=OFF

# -j$(nproc) OOM-kills a 16 GB runner: imp's four CUTLASS TUs peak at
# 5.2-7.9 GB resident each and start within 7 s of each other, which is exit 137
# with no compiler diagnostic. imp ships scripts/build_jobs.sh for exactly this;
# it reads the cgroup limit when there is one. Reused instead of reinvented.
JOBS=$(sh src/scripts/build_jobs.sh)
echo "building with -j${JOBS} (nproc=$(nproc))"
cmake --build build --config Release -j"$JOBS"

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