# Quick Start Guide

Get pre-built llama.cpp CUDA 13.2 binaries running in 5 minutes.

## Prerequisites

1. NVIDIA GPU, compute capability **7.5 or higher** (RTX 5090 = 12.0)
2. NVIDIA driver **>= 580.13** (CUDA 13.2 minimum)
3. Linux x86_64 (Ubuntu 24.04 compatible)
4. The CUDA runtime is **bundled** in the tarball — no toolkit install needed

## Step 1: Check Your GPU

```bash
nvidia-smi --query-gpu=name,compute_cap --format=csv
```

RTX 5090 reports `compute_cap 12.0`. Any value >= 7.5 works.

## Step 2: Check Your Driver

```bash
nvidia-smi | grep "Driver Version"
```

| CUDA | Min driver (Linux) |
|------|---------------------|
| 13.2 | **>= 580.13** ← this fork |
| 12.8 | >= 570.15 |
| 12.6 | >= 560.28 |

If your driver is older than 580.13, update it or the binary will refuse to load.

## Step 3: Download Binaries

1. Go to [Releases](../../releases/latest)
2. Download the fork tarball you want, e.g. `llama.cpp-cuda-13.2-turboquant-amd64.tar.gz`
   (also available: `vanilla`, `atomic`, `prism`)

```bash
# example: turboquant fork
wget https://github.com/tayuLuc/yet-another-llama.cpp-cuda-fork/releases/download/cuda-13.2-build-20260718/llama.cpp-cuda-13.2-turboquant-amd64.tar.gz
```

## Step 4: Extract

```bash
tar -xzf llama.cpp-cuda-13.2-turboquant-amd64.tar.gz
cd cuda-13.2/turboquant
```

## Step 5: Download a Model

```bash
wget https://huggingface.co/TheBloke/Llama-2-7B-GGUF/resolve/main/llama-2-7b.Q4_K_M.gguf
```

## Step 6: Run

```bash
# Chat
./llama-cli -m llama-2-7b.Q4_K_M.gguf -p "Hello, how are you?"

# Server (http://localhost:8080)
./llama-server -m llama-2-7b.Q4_K_M.gguf
```

### Common Options
```bash
./llama-cli -m model.gguf -ngl 999          # offload all layers to GPU
./llama-cli -m model.gguf -c 4096           # 4K context
./llama-cli -m model.gguf --temp 0.7         # temperature
./llama-cli -m model.gguf --seed 42         # reproducible
./llama-bench -m model.gguf -o json > bench.json
```

## Verify CUDA Works

You should see (note `compute capability 12.0` for RTX 5090):
```
ggml_cuda_init: CUDA_USE_TENSOR_CORES: yes
ggml_cuda_init: found 1 CUDA devices:
  Device 0: NVIDIA GeForce RTX 5090, compute capability 12.0
```

## Troubleshooting

**"CUDA driver version is insufficient"** → update driver to >= 580.13, or use an older CUDA build.

**"no CUDA-capable device is detected"** → `nvidia-smi` to confirm GPU visible; `sudo modprobe nvidia` if modules missing.

**Out of memory** → smaller model, Q4_K_M quant, `-c 2048`, `-ngl 32`.

**Missing shared libs** → the runtime is bundled in the tarball; ensure you extracted the whole archive and `chmod +x llama-*`.
