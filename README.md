# yet-another-llama.cpp-cuda-fork

Builds **4 llama.cpp forks** for **CUDA 13.2 / RTX 5090 (sm_120)**, amd64 only:

| Fork        | Source repo                              |
|-------------|------------------------------------------|
| vanilla     | `ggml-org/llama.cpp`                     |
| turboquant  | `TheTom/llama-cpp-turboquant`            |
| atomic      | `AtomicBot-ai/atomic-llama-cpp-turboquant` |
| prism       | `PrismML-Eng/llama.cpp`                  |

Built binaries are published as GitHub Releases; a downstream repo
([`llama-swap-cuda-images`](https://github.com/tayuLuc/llama-swap-cuda-images))
packs all four into a single Docker image with `llama-swap` in front.

## What gets built

For every fork we detect **two independent sources** and emit one release each:

- **stable** — latest GitHub Release of the fork (we only use its source commit,
  never the released binaries). The SHA comes from `VERSION.txt` (`ref:` field)
  inside the fork build.
- **nightly** — HEAD commit of the fork's tracked branch.

So up to **8 releases** per run (4 forks × 2 modes). Each release contains
`llama-server`, `llama-cli`, `llama-bench`, and `VERSION.txt`.

The CUDA runtime `.so` libraries (`libcudart`, `libcublas`, `libcublasLt`) are
**not** bundled inside fork tarballs. Instead, the **vanilla** release also
ships a single shared asset `cuda-runtime-13.2-amd64.tar.gz` — download it once
and place its `.so` files next to any fork's binaries (or set
`LD_LIBRARY_PATH`) for local, non-Docker use. The llama-swap Docker image does
not need it: its base `nvidia/cuda:13.2-runtime` already provides CUDA.

## Release tag scheme

```
<fork>-<sha12>              # stable, e.g. vanilla-571d0d540df0
<fork>-nightly-<sha12>      # nightly (prerelease), e.g. vanilla-nightly-571d0d540df0
```

## How it works

`build-cuda.yml` runs three stages:

1. **`check-forks`** — reads `forks.json` and builds a matrix of fork × mode.
   Each item carries the resolved source commit (`ref`), the release tag to
   publish, and the subdir the binaries land in.
2. **`build`** — 8 parallel jobs. Each runs `scripts/build-inside.sh` inside
   `nvidia/cuda:13.2.0-cudnn-devel-ubuntu24.04` with:
   - UI disabled (`-DLLAMA_BUILD_UI=OFF -DLLAMA_USE_PREBUILT_UI=OFF -DLLAMA_BUILD_WEBUI=OFF`)
   - CUDA on, architectures `75;80;86;89;90;100;120`
   - ccache for incremental rebuilds
   Each job publishes its own release on success, **independently** — a failure
   in one fork does not block the others.
3. **`trigger-swap`** — runs after all builds (`if: always()`). If at least one
   release was published today, it fires `workflow_dispatch` on
   `llama-swap-cuda-images` with `mode=stable|nightly` (nightly if any matrix
   item is nightly), which builds and pushes the combined Docker image to GHCR.

## Triggers

- `workflow_dispatch` with `force_build` (build all forks regardless of change)
- daily `schedule` (catches new releases / branch moves)
- `push` to `main`

## Layout

```
forks.json                 # source of truth: which forks/branches to build
scripts/build-inside.sh    # the actual cmake + build + packaging steps
.github/workflows/build-cuda.yml
```

## System requirements (runtime)

- NVIDIA GPU, compute capability **7.5+** (12.0 for RTX 5090)
- **NVIDIA driver >= 580.13** (CUDA 13.2)
- Linux x86_64. For local (non-Docker) use, grab `cuda-runtime-13.2-amd64.tar.gz`
  from the **vanilla** release and place its `.so` files beside the binaries
  (or `export LD_LIBRARY_PATH=…`). No full CUDA toolkit required — just the
  driver. The llama-swap Docker image provides CUDA via its base image.
