#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values (CUDA 13.2 + RTX 5090 / sm_120)
CUDA_VERSION=${1:-"13.2.0"}
LLAMA_TAG=${2:-"latest"}

echo -e "${GREEN}llama.cpp CUDA Local Build (best-of-all fork)${NC}"
echo "================================"
echo "CUDA Version: $CUDA_VERSION"
echo "llama.cpp Tag: $LLAMA_TAG"
echo ""

# Validate CUDA version and set parameters
case $CUDA_VERSION in
    12.8.1)
        CUDA_TAG="12.8.1-cudnn-devel-ubuntu24.04"
        ARCHITECTURES="75;80;86;89;90;100;120"
        ;;
    13.0.1)
        CUDA_TAG="13.0.1-cudnn-devel-ubuntu24.04"
        ARCHITECTURES="75;80;86;89;90;100;120"
        ;;
    13.2.0)
        # Default — required for Blackwell / RTX 5090 (sm_120)
        CUDA_TAG="13.2.0-cudnn-devel-ubuntu24.04"
        ARCHITECTURES="75;80;86;89;90;100;120"
        ;;
    *)
        echo -e "${RED}Error: Unsupported CUDA version $CUDA_VERSION${NC}"
        echo "Supported versions: 12.8.1, 13.0.1, 13.2.0"
        exit 1
        ;;
esac

# Get llama.cpp release info if not specified
if [ "$LLAMA_TAG" = "latest" ]; then
    echo -e "${YELLOW}Fetching latest llama.cpp release...${NC}"
    LLAMA_TAG=$(curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
    RELEASE_HASH=$(curl -s https://api.github.com/repos/ggml-org/llama.cpp/releases/latest | grep '"target_commitish":' | sed -E 's/.*"([^"]+)".*/\1/')
    echo "Latest release: $LLAMA_TAG (${RELEASE_HASH:0:8})"
else
    RELEASE_HASH=$(curl -s "https://api.github.com/repos/ggml-org/llama.cpp/git/refs/tags/$LLAMA_TAG" | grep '"sha":' | sed -E 's/.*"([^"]+)".*/\1/')
fi

echo ""
echo -e "${YELLOW}Building with:${NC}"
echo "  Docker Image: nvidia/cuda:$CUDA_TAG"
echo "  Architectures: $ARCHITECTURES"
echo ""

# Clean previous builds
rm -rf binaries local-build
mkdir -p binaries/cuda-$CUDA_VERSION

# Run build in Docker (mirrors CI: ccache + lld + bundled CUDA runtime)
echo -e "${GREEN}Starting Docker build...${NC}"
docker run --rm -v $PWD:/workspace \
    nvidia/cuda:$CUDA_TAG \
    bash -c "
        set -e
        cd /workspace

        echo '=> Installing dependencies...'
        apt-get update -qq
        apt-get install -y --no-install-recommends -qq git cmake ninja-build build-essential libssl-dev ca-certificates ccache lld > /dev/null
        apt-get clean
        rm -rf /var/lib/apt/lists/*

        echo '=> Cloning llama.cpp...'
        git clone https://github.com/ggml-org/llama.cpp.git local-build
        cd local-build
        git checkout $RELEASE_HASH

        echo '=> Configuring build (Ninja + ccache + lld)...'
        export LIBRARY_PATH=\"/usr/local/cuda/lib64/stubs\${LIBRARY_PATH:+:\$LIBRARY_PATH}\"
        ln -sf /usr/local/cuda/lib64/stubs/libcuda.so /usr/local/cuda/lib64/stubs/libcuda.so.1
        cmake -B build -S . \
            -G Ninja \
            -DGGML_CUDA=ON \
            -DCMAKE_C_COMPILER_LAUNCHER=ccache \
            -DCMAKE_CXX_COMPILER_LAUNCHER=ccache \
            -DCMAKE_CUDA_COMPILER_LAUNCHER=ccache \
            -DCMAKE_CUDA_ARCHITECTURES='$ARCHITECTURES' \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=ON \
            -DGGML_NATIVE=OFF \
            -DLLAMA_BUILD_TESTS=OFF \
            -DLLAMA_BUILD_EXAMPLES=OFF \
            -DCMAKE_EXE_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs' \
            -DCMAKE_SHARED_LINKER_FLAGS='-fuse-ld=lld -Wl,-rpath-link,/usr/local/cuda/lib64/stubs'

        echo '=> Building with Ninja...'
        cmake --build build --config Release -j\$(nproc)

        echo '=> Copying binaries...'
        cd /workspace
        cp -r local-build/build/bin/* binaries/cuda-$CUDA_VERSION/

        # Bundle CUDA runtime so users don't need the full toolkit
        echo '=> Bundling CUDA runtime...'
        CUDA_LIB=/usr/local/cuda/targets/x86_64-linux/lib
        cp -a \${CUDA_LIB}/libcudart.so* binaries/cuda-$CUDA_VERSION/
        cp -a \${CUDA_LIB}/libcublas.so* binaries/cuda-$CUDA_VERSION/
        cp -a \${CUDA_LIB}/libcublasLt.so* binaries/cuda-$CUDA_VERSION/

        # Strip executables only (not .so)
        echo '=> Stripping binaries...'
        find binaries/cuda-$CUDA_VERSION/ -type f -executable ! -name '*.so*' -exec strip {} \; 2>/dev/null || true

        echo '=> Creating version info...'
        cat > binaries/cuda-$CUDA_VERSION/VERSION.txt << EOF
llama.cpp version: $LLAMA_TAG
CUDA version: $CUDA_VERSION
Architectures: $ARCHITECTURES
Build date: \$(date -u +%Y-%m-%d)
Build hash: $RELEASE_HASH
EOF

        echo '=> Build complete!'
    "

# Create tarball
echo ""
echo -e "${GREEN}Creating tarball...${NC}"
cd binaries
tar -czf llama.cpp-$LLAMA_TAG-cuda-$CUDA_VERSION-amd64.tar.gz cuda-$CUDA_VERSION
cd .

# Show results
echo ""
echo -e "${GREEN}✓ Build successful!${NC}"
echo ""
echo "Binaries location: binaries/cuda-$CUDA_VERSION/"
echo "Tarball: binaries/llama.cpp-$LLAMA_TAG-cuda-$CUDA_VERSION-amd64.tar.gz"
echo ""
echo "Built binaries:"
ls -lh binaries/cuda-$CUDA_VERSION/

# Clean up source
rm -rf local-build

echo ""
echo -e "${GREEN}Local build complete!${NC}"
