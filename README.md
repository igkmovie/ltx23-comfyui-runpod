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

After setup, start ComfyUI with:

```bash
cd /workspace/ComfyUI
python3 main.py --listen 0.0.0.0 --port 8188
```

