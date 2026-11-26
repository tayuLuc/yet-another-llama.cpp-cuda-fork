#!/usr/bin/env bash
# Build basalt inside the CUDA container and emit the author's release tree
# into binaries/${SUBDIR}/ so the llama-swap image fetcher unpacks it into
# /opt/llama/basalt unchanged (bin/basalt, serve/, tools/, requirements.txt).
#
# basalt is not a llama.cpp fork: its cmake options are BASALT_*, and its own
# release.yml (probed 27.11) configures with -DBASALT_MODELS=all on CUDA 13.0,
# builds the default target, then packs the tree with tools/package_release.py
# (one top-level dir: executables + serve/ + tools/ + data/ + requirements).
# This lane mirrors that recipe inside the lane's CUDA container; the packer
# stays theirs so the tar layout never drifts from the release archives the
# image already consumes (cross-repo lane, jesdga95/basalt).
# Env: REPO, REF, RELTAG (stable tag or empty), SUBDIR, MODE, ARCHS, CUDA_TAG.
set -e

# Same malformed-index workaround as the infernix lane (de mirrors, drop cuda apt
# list), applied to BOTH source formats: the 13.2 CUDA base ships the legacy
# /etc/apt/sources.list (only the 13.4 base moved to deb822 ubuntu.sources, which
# is all the infernix-lane sed knew about) - run 45801656634 died on
# security.ubuntu.com mid-sync ("File has unexpected size", exit 100) because the
# rewrite never touched its file.
for f in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do
  sed -i 's|archive.ubuntu.com|de.archive.ubuntu.com|g; s|security.ubuntu.com|de.archive.ubuntu.com|g' "$f" 2>/dev/null || true
done
rm -f /etc/apt/sources.list.d/cuda*.list

# Mirror sync is transient (the Release file was minutes old against a moving
# Packages.gz): one retry, then fail loud.
apt-get update -qq || { echo "apt-get update failed, retrying in 30s (mirror sync?)"; sleep 30; apt-get update -qq; }
# Their Linux toolchain (actions/toolchain/action.yml:24-25): ninja + cuda-nvcc/
# cudart-dev/crt/cccl/nvrtc-dev/cublas-dev - all in the nvidia/cuda devel image
# we run in, so the apt list here is their runner additions plus python3 for
# the packer (release.yml uses setup-python 3.12; ubuntu24.04 python3 is 3.12).
apt-get install -y --no-install-recommends \
    cmake ninja-build build-essential git ccache python3
apt-get clean
rm -rf /var/lib/apt/lists/*

missing=""
for t in git cmake ninja ccache strip objdump python3; do
  command -v "$t" >/dev/null 2>&1 || missing="$missing $t"
done
if [ -n "$missing" ]; then echo "FATAL: missing tools:$missing" >&2; exit 1; fi

ccache -M 3G
ccache -z

cd /workspace
git clone "https://github.com/${REPO}.git" src
cd src
git checkout "$REF"

cmake -B build -S . \
  -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DBUILD_TESTING=OFF \
  -DBASALT_MODELS=all \
  -DCMAKE_CUDA_ARCHITECTURES="${ARCHS:-120}" \
  -DCMAKE_C_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
  -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache

# Their build step is plain `cmake --build build -j nproc` (no explicit target).
cmake --build build -j"$(nproc)"

echo '=== CCache Statistics ==='
ccache -s

# The author's packer wants a release tag; nightly builds are addressed by sha
# (RELTAG is empty for mode=nightly, per the workflow matrix).
TAG="${RELTAG:-nightly-$(git rev-parse --short "$REF")}"
python3 tools/package_release.py --tag "$TAG" --platform linux-x64 --out pkg

cd /workspace
mkdir -p "binaries/${SUBDIR}"
# The archive holds one top-level dir (basalt-<tag>-linux-x64/); flatten it
# into the lane subdir so the tar the workflow creates carries the tree root
# the image fetcher expects (same "flatten one level" rule as its lane).
tar -xzf "src/pkg/basalt-${TAG}-linux-x64.tar.gz" -C "binaries/${SUBDIR}" --strip-components=1

[ -x "binaries/${SUBDIR}/bin/basalt" ] || { echo "FATAL: bin/basalt missing after unpack" >&2; ls -R "binaries/${SUBDIR}" | head >&2; exit 1; }
find "binaries/${SUBDIR}/bin/" -type f -executable -exec strip {} \; 2>/dev/null || true

{
  echo "engine: ${REPO}"
  echo "mode: ${MODE:-nightly}"
  echo "ref: ${REF}"
  echo "tag: ${TAG}"
  echo "CUDA version: ${CUDA_TAG}"
  echo "Build date: $(date -u +%Y-%m-%d)"
} > "binaries/${SUBDIR}/VERSION.txt"

# Sanity: the engine binary must link libcudart.so.13 (a CUDA-12 build would
# pass the build and die in the swap image at exec). Same doctrine as the
# infernix lane, including the libcuda.so.1 stub exception (driver-provided).
SONAME=$(objdump -p "binaries/${SUBDIR}/bin/basalt" | awk '/NEEDED/ {print $2}' | grep -c 'libcudart\.so\.13' || true)
[ "${SONAME}" -gt 0 ] || { echo "FATAL: bin/basalt does not link libcudart.so.13" >&2; ldd "binaries/${SUBDIR}/bin/basalt" | head >&2; exit 1; }
mkdir -p /tmp/cuda-stubs
[ -f /usr/local/cuda/lib64/stubs/libcuda.so ] && cp /usr/local/cuda/lib64/stubs/libcuda.so /tmp/cuda-stubs/libcuda.so.1
LD_LIBRARY_PATH=/tmp/cuda-stubs ldd "binaries/${SUBDIR}/bin/basalt" \
  | awk '/not found/ && $1 != "libcuda.so.1" {print "FATAL unresolved:", $1; exit 1}'
echo "bin/basalt links libcudart.so.13 - OK"
ls -lh "binaries/${SUBDIR}/" "binaries/${SUBDIR}/bin/"
