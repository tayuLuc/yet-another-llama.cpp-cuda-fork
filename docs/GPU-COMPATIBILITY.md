# GPU Compatibility Reference (CUDA 13.2 fork)

## Your RTX 5090

| Property | Value |
|---|---|
| Architecture | Blackwell (consumer) |
| Compute capability | **12.0** (`sm_120`) |
| Required CUDA | **13.2** (12.8+ minimum, 13.x recommended) |
| Min driver | 580.13 |

This fork compiles with `-DCMAKE_CUDA_ARCHITECTURES='75;80;86;89;90;100;120'`,
so **every** GPU below is supported by the same tarball.

## Compute Capability → This Fork

| CC | Family | Examples | In 13.2 build? |
|----|--------|---------|:---:|
| 7.5 | Turing | T4, RTX 20xx | ✅ |
| 8.0 | Ampere DC | A100, A30 | ✅ |
| 8.6 | Ampere | RTX 30xx, A40 | ✅ |
| 8.9 | Ada / Hopper-L | RTX 40xx, L4, L40 | ✅ |
| 9.0 | Hopper | H100, H200 | ✅ |
| 10.0 | Blackwell DC | B200, GB200 | ✅ |
| **12.0** | **Blackwell consumer** | **RTX 5090, RTX 50 series** | ✅ |

## Minimum Driver by CUDA

| CUDA | Min driver (Linux) |
|------|---------------------|
| 12.4 | 550.54 |
| 12.6 | 560.28 |
| 12.8 | 570.15 |
| 12.9 | 580.13 |
| **13.2** | **580.13** |

## Find Your GPU's Compute Capability

```bash
nvidia-smi --query-gpu=name,compute_cap --format=csv
# or
python -c "import torch; print(torch.cuda.get_device_capability(0))"
```

## Notes

- "no kernel image is available for execution" means the binary wasn't built for your
  `sm_XX`. This fork covers 7.5 → 12.0, so that error should never occur here.
- Older GPUs (Turing/Ada) run fine on the CUDA 13.2 build — no need for an older CUDA version unless your driver is < 580.13.
