#!/usr/bin/env bash
set -Eeuo pipefail

COMFY_ROOT="/workspace/ComfyUI"
PROJECT_ROOT="/workspace/ltx23-comfyui-runpod"
PYTHON="${PYTHON:-python3}"

mkdir -p /workspace

echo "==> Preparing ComfyUI at ${COMFY_ROOT}"
if [[ ! -d "${COMFY_ROOT}/.git" ]]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_ROOT}"
else
  git -C "${COMFY_ROOT}" pull --ff-only
fi

echo "==> Installing ComfyUI requirements"
"${PYTHON}" -m pip install --upgrade pip
"${PYTHON}" -m pip install -r "${COMFY_ROOT}/requirements.txt"

echo "==> Installing official LTXVideo nodes"
mkdir -p "${COMFY_ROOT}/custom_nodes"
if [[ ! -d "${COMFY_ROOT}/custom_nodes/ComfyUI-LTXVideo/.git" ]]; then
  git clone --depth 1 https://github.com/Lightricks/ComfyUI-LTXVideo.git \
    "${COMFY_ROOT}/custom_nodes/ComfyUI-LTXVideo"
else
  git -C "${COMFY_ROOT}/custom_nodes/ComfyUI-LTXVideo" pull --ff-only
fi
if [[ -f "${COMFY_ROOT}/custom_nodes/ComfyUI-LTXVideo/requirements.txt" ]]; then
  "${PYTHON}" -m pip install -r "${COMFY_ROOT}/custom_nodes/ComfyUI-LTXVideo/requirements.txt"
fi

echo "==> Creating model directories"
mkdir -p \
  "${COMFY_ROOT}/models/checkpoints" \
  "${COMFY_ROOT}/models/text_encoders" \
  "${COMFY_ROOT}/models/loras" \
  "${COMFY_ROOT}/models/vae"

# Remove the incompatible/stale encoder variant. ComfyUI may otherwise keep
# selecting it instead of the public fp4 encoder used by this workflow.
rm -f "${COMFY_ROOT}/models/text_encoders/gemma_3_12B_it_fp8_scaled.safetensors"

download() {
  local url="$1"
  local destination="$2"
  if [[ -s "${destination}" ]]; then
    echo "exists: ${destination}"
    return
  fi
  echo "downloading: ${destination}"
  curl -L --fail --retry 5 --retry-delay 5 -C - \
    -o "${destination}.part" "${url}"
  mv "${destination}.part" "${destination}"
}

# Public Comfy-Org quantized Gemma encoder; avoids the gated Google repo.
download \
  "https://huggingface.co/Comfy-Org/ltx-2/resolve/main/split_files/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors?download=true" \
  "${COMFY_ROOT}/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors"

# LTX-2.3 distilled checkpoint. This is a large download (about 43 GB).
download \
  "https://huggingface.co/Lightricks/LTX-2.3/resolve/main/ltx-2.3-22b-distilled-1.1.safetensors?download=true" \
  "${COMFY_ROOT}/models/checkpoints/ltx-2.3-22b-distilled-1.1.safetensors"

echo "==> Verifying files"
ls -lh \
  "${COMFY_ROOT}/models/text_encoders/gemma_3_12B_it_fp4_mixed.safetensors" \
  "${COMFY_ROOT}/models/checkpoints/ltx-2.3-22b-distilled-1.1.safetensors"

echo
echo "Setup complete. Restart ComfyUI, then open the LTX-2.3 workflow."
