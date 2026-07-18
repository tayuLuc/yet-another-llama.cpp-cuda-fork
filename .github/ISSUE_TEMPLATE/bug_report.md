---
name: Bug Report
about: Report a problem with the built binaries
title: '[BUG] '
labels: bug
assignees: ''
---

## Description
A clear and concise description of the bug.

## System Information
**GPU Model:**
```
# Output of: nvidia-smi --query-gpu=name,compute_cap --format=csv
```

**NVIDIA Driver Version:**
```
# Output of: nvidia-smi | grep "Driver Version"
```

**Operating System:**
```
# Output of: uname -a && lsb_release -a
```

**Build Information:**
- CUDA Version: [e.g., 13.2]
- llama.cpp Version: [e.g., b9536]
- Download Link: [link to release you downloaded]

## Steps to Reproduce
1. Download build from [link]
2. Extract with `tar -xzf ...`
3. Run command: `./llama-cli ...`
4. See error

## Expected Behavior
What you expected to happen.

## Actual Behavior
What actually happened.

## Error Output
```
Paste the full error output here
```

## Additional Context
Add any other context about the problem here.

## Checklist
- [ ] I have checked the Troubleshooting Guide
- [ ] I have verified my GPU is supported (RTX 5090 = compute 12.0)
- [ ] I have the minimum required NVIDIA driver (>= 580.13 for CUDA 13.2)
- [ ] This is about the build process or binaries (not llama.cpp functionality)
