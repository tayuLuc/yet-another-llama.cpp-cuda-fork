# llama.cpp Multi-Fork CUDA Builds

Pre-built **CUDA 13.2** binaries for **four** llama.cpp forks, amd64 only, targeting
**NVIDIA RTX 5090 (Blackwell, compute capability 12.0 / `sm_120`)** plus every prior
generation (Turing → Hopper). Each fork is built from its own source and unpacked into
its own directory so the binaries never collide.

## What gets built

All four use the **same standard CMake build** (`-DGGML_CUDA=ON`, Ninja). They differ only
in source repo / branch:

| Fork | Source | Branch | What it adds |
|------|--------|--------|--------------|
| `vanilla` | [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) | release tag | Upstream — tracked by latest release tag |
| `turboquant` | [TheTom/llama-cpp-turboquant](https://github.com/TheTom/llama-cpp-turboquant) | `feature/turboquant-kv-cache` | TurboQuant+ KV/weight quantization |
| `atomic` | [AtomicBot-ai/atomic-llama-cpp-turboquant](https://github.com/AtomicBot-ai/atomic-llama-cpp-turboquant) | `feature/turboquant-kv-cache` | TheTom + Gemma4 MTP, Qwen3.6 NextN speculative decoding |
| `prism` | [PrismML-Eng/llama.cpp](https://github.com/PrismML-Eng/llama.cpp) | `prism` | `Q2_0` ternary quantization (Bonsai models) |

Build matrix is defined in [`forks.json`](forks.json) — edit that file to add/remove forks.

## Why this repo

The official llama.cpp repo ships no pre-built CUDA binaries. This repo fills that gap and
extends it across multiple community forks:

- Built against **CUDA 13.2** (required for Blackwell / RTX 50 series)
- Compute capabilities **7.5 → 12.0**
- **Bundles the CUDA runtime** (cudart, cublas, cublasLt) in each tarball — no toolkit install
- Per-fork change detection: vanilla by release tag, forks by branch HEAD commit
- GitHub Releases carry one tarball per fork

## Supported configurations

- **CUDA:** 13.2
- **Host arch:** amd64 (x86_64 Linux), tarballs suffixed `-amd64.tar.gz`
- **GPU archs:** `75;80;86;89;90;100;120` (T4/RTX20 → A100 → RTX30/40 → H100 → B200 → RTX5090)

## Usage

### Download a single fork

```bash
# from the Releases page, e.g. cuda-13.2-build-20260718
tar -xzf llama.cpp-cuda-13.2-turboquant-amd64.tar.gz
cd cuda-13.2/turboquant
./llama-server -m model.gguf
cat VERSION.txt   # shows fork, ref, CUDA version, archs
```

### Run all four behind llama-swap (recommended)

This repo ships a Docker image that bundles all four forks and runs
[llama-swap](https://github.com/mostlygeek/llama-swap) in front, selecting the right
binary per model:

```bash
# 1. Build the image (downloads the 4 tarballs from this repo's release)
docker build -t llama-multifork \
  --build-arg REPO=tayuLuc/yet-another-llama.cpp-cuda-fork \
  --build-arg RELEASE=cuda-13.2-build-20260718 .

# 2. Run (needs nvidia-container-toolkit on the host)
docker compose up -d
# llama-swap OpenAI-compatible API on :8080
```

Model→fork mapping lives in [`llama-swap/config.yaml`](llama-swap/config.yaml). The default
`llama-server` on PATH is `vanilla`; override per-model via `llama_cpp_binary`.

## System requirements

- NVIDIA GPU, compute capability **7.5+** (12.0 for RTX 5090)
- **NVIDIA driver >= 580.13** (CUDA 13.2)
- Linux x86_64, nvidia-container-toolkit for the Docker path
- CUDA runtime is **bundled** — no toolkit needed

## Build process

- Runs **daily at 00:00 UTC** via cron
- `check-forks` reads `forks.json` and rebuilds only forks whose ref changed
  (vanilla: new release tag; others: new branch HEAD commit)
- `force_build` workflow_dispatch input rebuilds everything
- Each build: Docker `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04` + CMake/Ninja + `ccache` (3 GB) + `lld`
- Tarballs uploaded as artifacts → one GitHub Release per day (`cuda-13.2-build-YYYYMMDD`)

## Manual build

```bash
git clone https://github.com/tayuLuc/yet-another-llama.cpp-cuda-fork
cd yet-another-llama.cpp-cuda-fork
./scripts/local-build.sh            # mirrors CI, CUDA 13.2 + latest vanilla
```

To change CUDA version / architectures / forks, edit `forks.json` and
`.github/workflows/build-cuda.yml`.

## License

Build scripts only. llama.cpp binaries are subject to the
[llama.cpp MIT License](https://github.com/ggml-org/llama.cpp/blob/master/LICENSE).

## Credits

- [llama.cpp](https://github.com/ggml-org/llama.cpp) by Georgi Gerganov and contributors
- CUDA 13 / runtime-bundling base by [Syrunekai](https://github.com/Syrunekai)
- ccache/lld speedups by [Kishan200308](https://github.com/Kishan200308)
- NixOS flake by [JL2718](https://github.com/JL2718)
- Multi-fork matrix design for this repo
