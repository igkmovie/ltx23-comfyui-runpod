# LTX-2.3 ComfyUI on RunPod (and other GPU hosts)

This repository contains a reproducible setup for a clean GPU host running
ComfyUI with LTX-2.3 workflows. It intentionally does **not** store the
ComfyUI checkout or model files in Git - the bootstrap script downloads
exactly what the workflow you choose needs, at setup time.

## Target host

- GPU: A40 48 GB (or another GPU with at least 48 GB VRAM for the bf16
  checkpoint; the `fp8` checkpoint fits smaller GPUs)
- RunPod image: `runpod/pytorch:1.0.2-cu1281-torch280-ubuntu2404` with a
  persistent volume mounted at `/workspace`
- Also works on a plain GPU VM (e.g. GCP Compute Engine with a CUDA-capable
  image) - see "Other hosts" below.

## Setup

From the host terminal:

```bash
git clone https://github.com/igkmovie/ltx23-comfyui-runpod.git /workspace/ltx23-comfyui-runpod
bash /workspace/ltx23-comfyui-runpod/scripts/bootstrap-runpod.sh <workflow-name>
```

`<workflow-name>` is any file in `workflows/` (with or without the `.json`
suffix), for example:

```bash
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple_FP8
bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_NoLoRA
```

Running the script with no argument prints usage and the list of available
workflows.

The script only downloads the models the *selected* workflow actually
references (resolved via `models-manifest.json`), then copies every
workflow in `workflows/` into ComfyUI so you can switch between them from
the UI once their models are present. It is resumable - if a large model
download stops, run it again and `curl -C -` continues from the existing
file.

Pass `--no-start` as a second argument to skip launching ComfyUI (useful for
pre-warming a host without starting the server yet).

### Available workflows

| Workflow | Notes |
|---|---|
| `LTX-2.3_Distilled_I2V_Simple` | Single-path image-to-video, no audio output, bf16 checkpoint (~46 GB). Recommended starting point. |
| `LTX-2.3_Distilled_I2V_Simple_FP8` | Same graph, fp8-quantized checkpoint (~29.5 GB). Less data to read off disk, so the first checkpoint load into memory is noticeably faster. |
| `LTX-2.3_Distilled_NoLoRA` | Full audio+video dual-path workflow (distilled + full quality branches). |
| `LTX-2.3_Distilled_NoLoRA_NoAudio` | Same as above with the audio decode/save nodes removed. |
| `LTX-2.3_Distilled_PublicGemma` | Dual-path workflow using the public Gemma text encoder path with explicit audio VAE decode. |

### Adding a new workflow

1. Drop the workflow JSON into `workflows/`.
2. Run `python scripts/register-workflow-models.py workflows/<name>.json` to
   scaffold any new model filenames into `models-manifest.json` (guessed
   subdir, `TODO` url placeholder).
3. Fill in the real download url for each new entry in
   `models-manifest.json`.
4. `bash scripts/bootstrap-runpod.sh <name>` will now download exactly what
   that workflow needs.

`bootstrap-runpod.sh` refuses to run (with a clear error pointing at
`register-workflow-models.py`) if a workflow references a model with no
manifest entry, or one whose url is still a `TODO` placeholder - it never
silently skips a required download.

### Other hosts (e.g. GCP)

`COMFY_ROOT` and `PROJECT_ROOT` default to the RunPod `/workspace`
convention but can be overridden for hosts that mount storage elsewhere:

```bash
COMFY_ROOT=/opt/ComfyUI PROJECT_ROOT=/opt/ltx23-comfyui-runpod \
  bash scripts/bootstrap-runpod.sh LTX-2.3_Distilled_I2V_Simple
```

Nothing else in the script is RunPod-specific - it just needs a Linux host
with an NVIDIA GPU, git, curl, and Python 3.

The bootstrap removes the stale `gemma_3_12B_it_fp8_scaled.safetensors` file
before installing the public `gemma_3_12B_it_fp4_mixed.safetensors` encoder.
It also verifies that PyTorch can see the GPU and installs CUDA 12.8 wheels
only when the base image does not already provide usable CUDA support.

The setup script starts ComfyUI automatically on port `8188` (override with
`COMFY_PORT`) after all models, dependencies, nodes, and the selected
workflow's checks pass. Keep the terminal open while using the GUI.
