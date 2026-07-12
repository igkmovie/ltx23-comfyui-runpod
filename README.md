# LTX-2.3 ComfyUI on RunPod

This repository contains the reproducible setup for a clean RunPod Pod.
It intentionally does **not** store the ComfyUI checkout or model files in Git.
The Pod downloads those into `/workspace` at setup time.

## Target Pod

- GPU: A40 48 GB (or another GPU with at least 48 GB VRAM)
- Image: `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404`
- Persistent volume mounted at `/workspace`
- ComfyUI path: `/workspace/ComfyUI`

## Setup

From the Pod terminal:

```bash
git clone https://github.com/igkmovie/ltx23-comfyui-runpod.git /workspace/ltx23-comfyui-runpod
bash /workspace/ltx23-comfyui-runpod/scripts/bootstrap-runpod.sh
```

The script is resumable. If a large model download stops, run it again and
`curl -C -` continues from the existing file.

The bootstrap removes the stale `gemma_3_12B_it_fp8_scaled.safetensors` file
before installing the public `gemma_3_12B_it_fp4_mixed.safetensors` encoder.
It also verifies that PyTorch can see the Pod GPU and installs CUDA 12.8
wheels only when the base image does not already provide usable CUDA support.

The setup script starts ComfyUI automatically on port `8188` after all
models, dependencies, nodes, and workflow checks pass. Keep the terminal open
while using the GUI.
