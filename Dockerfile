# Multi-fork llama.cpp CUDA image + llama-swap
#
# Downloads the 4 prebuilt llama.cpp CUDA 13.2 tarballs published by this repo's
# GitHub Releases, unpacks each fork into /opt/llama/<name>/bin, and runs
# llama-swap in front of them. Each fork is selected per-model in the
# llama-swap config (see llama-swap/config.yaml).
#
# Build:
#   docker build -t llama-multifork \
#     --build-arg REPO=tayuLuc/yet-another-llama.cpp-cuda-fork \
#     --build-arg RELEASE=cuda-13.2-build-20260718 \
#     .
#
# The default llama-server on PATH (/usr/local/bin/llama-server) is the
# vanilla build; override per-model via llama-swap's `llama_cpp_binary` path.

FROM ubuntu:24.04

ARG REPO=tayuLuc/yet-another-llama.cpp-cuda-fork
ARG RELEASE=cuda-13.2-build-20260718
ARG CUDA_SHORT=13.2

ENV DEBIAN_FRONTEND=noninteractive \
    LLAMA_SWAP_VERSION=v1.1.2 \
    CUDA_SHORT=${CUDA_SHORT}

RUN apt-get update -qq && \
    apt-get install -y --no-install-recommends curl ca-certificates jq && \
    rm -rf /var/lib/apt/lists/*

# Download and unpack every fork tarball published by this repo.
# Tarball layout: cuda-13.2/<fork>/llama-server (plus bundled CUDA runtime libs)
RUN set -eux; \
    BASE="https://github.com/${REPO}/releases/download/${RELEASE}"; \
    mkdir -p /opt/llama /tmp/dl; \
    for F in vanilla turboquant atomic prism; do \
      URL="${BASE}/llama.cpp-cuda-${CUDA_SHORT}-${F}-amd64.tar.gz"; \
      echo "Fetching ${URL}"; \
      curl -fsSL "${URL}" -o "/tmp/dl/${F}.tar.gz" || { echo "MISSING: ${URL}"; continue; }; \
      mkdir -p "/tmp/dl/${F}"; \
      tar -xzf "/tmp/dl/${F}.tar.gz" -C "/tmp/dl/${F}"; \
      # tarball root is cuda-13.2/<fork>/...
      mv "/tmp/dl/${F}/cuda-${CUDA_SHORT}/${F}" "/opt/llama/${F}"; \
      chmod +x "/opt/llama/${F}/llama-server" "/opt/llama/${F}/llama-cli" 2>/dev/null || true; \
      echo "Installed fork: ${F} -> /opt/llama/${F}"; \
    done; \
    rm -rf /tmp/dl

# Default llama-server on PATH = vanilla build.
RUN ln -sf /opt/llama/vanilla/llama-server /usr/local/bin/llama-server && \
    ln -sf /opt/llama/vanilla/llama-cli /usr/local/bin/llama-cli

# Install llama-swap binary.
RUN set -eux; \
    ARCH=$(dpkg --print-architecture); \
    URL="https://github.com/mostlygeek/llama-swap/releases/download/${LLAMA_SWAP_VERSION}/llama-swap-linux-${ARCH}"; \
    curl -fsSL "${URL}" -o /usr/local/bin/llama-swap; \
    chmod +x /usr/local/bin/llama-swap

# Per-model fork selection lives here; mount your own at runtime.
COPY llama-swap/config.yaml /etc/llama-swap/config.yaml

EXPOSE 8080
WORKDIR /models

# llama-swap serves OpenAI-compatible API and picks the right llama.cpp binary per model.
CMD ["llama-swap", "--config", "/etc/llama-swap/config.yaml", "--host", "0.0.0.0", "--port", "8080"]
