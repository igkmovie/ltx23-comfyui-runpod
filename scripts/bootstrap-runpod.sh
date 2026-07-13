#!/usr/bin/env bash
set -Eeuo pipefail

# COMFY_ROOT/PROJECT_ROOT default to the RunPod persistent-volume convention
# but can be overridden for other hosts (e.g. a GCP VM without /workspace):
#   COMFY_ROOT=/opt/ComfyUI PROJECT_ROOT=/opt/ltx23-comfyui-runpod \
#     bash scripts/bootstrap-runpod.sh <workflow-name>
COMFY_ROOT="${COMFY_ROOT:-/workspace/ComfyUI}"
PROJECT_ROOT="${PROJECT_ROOT:-/workspace/ltx23-comfyui-runpod}"
PYTHON="${PYTHON:-python3}"

usage() {
  echo "Usage: $0 <workflow-name-or-path> [--no-start]" >&2
  echo >&2
  echo "Available workflows in ${PROJECT_ROOT}/workflows:" >&2
  for f in "${PROJECT_ROOT}/workflows/"*.json; do
    echo "  - $(basename "${f}" .json)" >&2
  done
}

WORKFLOW_ARG="${1:-}"
if [[ -z "${WORKFLOW_ARG}" ]]; then
  usage
  exit 1
fi
NO_START="${2:-}"

if [[ -f "${WORKFLOW_ARG}" ]]; then
  WORKFLOW_PATH="${WORKFLOW_ARG}"
elif [[ -f "${PROJECT_ROOT}/workflows/${WORKFLOW_ARG}" ]]; then
  WORKFLOW_PATH="${PROJECT_ROOT}/workflows/${WORKFLOW_ARG}"
elif [[ -f "${PROJECT_ROOT}/workflows/${WORKFLOW_ARG}.json" ]]; then
  WORKFLOW_PATH="${PROJECT_ROOT}/workflows/${WORKFLOW_ARG}.json"
else
  echo "Workflow not found: ${WORKFLOW_ARG}" >&2
  usage
  exit 1
fi
echo "==> Selected workflow: ${WORKFLOW_PATH}"

mkdir -p "$(dirname "${COMFY_ROOT}")"

echo "==> Preparing ComfyUI at ${COMFY_ROOT}"
if [[ ! -d "${COMFY_ROOT}/.git" ]]; then
  git clone https://github.com/comfyanonymous/ComfyUI.git "${COMFY_ROOT}"
else
  git -C "${COMFY_ROOT}" pull --ff-only
fi

echo "==> Installing ComfyUI requirements"
"${PYTHON}" -m pip install --upgrade pip
"${PYTHON}" -m pip install -r "${COMFY_ROOT}/requirements.txt"
# ComfyUI's asset database imports SQLAlchemy directly. Keep it explicit because
# some base images do not install the transitive dependency from alembic.
"${PYTHON}" -m pip install "sqlalchemy>=2.0" "alembic>=1.13"

# Keep the CUDA PyTorch supplied by the base image. If it does not expose a
# usable CUDA build, install the matching public CUDA 12.8 wheels.
if ! "${PYTHON}" -c "import torch; raise SystemExit(0 if torch.cuda.is_available() else 1)"; then
  echo "CUDA PyTorch is unavailable; installing CUDA 12.8 wheels"
  "${PYTHON}" -m pip install --upgrade \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu128
fi

"${PYTHON}" -c "import torch; print('PyTorch:', torch.__version__); print('CUDA:', torch.version.cuda); print('GPU:', torch.cuda.get_device_name(0) if torch.cuda.is_available() else 'UNAVAILABLE'); raise SystemExit(0 if torch.cuda.is_available() else 1)"

echo "==> Resolving custom node repositories required by $(basename "${WORKFLOW_PATH}")"
mkdir -p "${COMFY_ROOT}/custom_nodes"
# Prints "repo_key<TAB>git_url<TAB>revision" for every custom-node repo the
# selected workflow needs (i.e. node classes not already provided by
# ComfyUI core), looked up in custom-nodes-manifest.json. Fails loudly if a
# required node class has no manifest entry, or its manifest repo is still
# a TODO-* placeholder - run scripts/register-workflow-nodes.py to
# scaffold missing entries, instead of silently skipping the install.
REQUIRED_REPOS="$("${PYTHON}" - "${COMFY_ROOT}" "${WORKFLOW_PATH}" "${PROJECT_ROOT}/custom-nodes-manifest.json" <<'PY'
import asyncio
import json
import sys

comfy_root, workflow_path, manifest_path = sys.argv[1], sys.argv[2], sys.argv[3]
workflow = json.loads(open(workflow_path, encoding="utf-8").read())
manifest = json.loads(open(manifest_path, encoding="utf-8").read())

required = {node["type"] for node in workflow.get("nodes", []) if "type" in node}

sys.path.insert(0, comfy_root)
import nodes
asyncio.run(nodes.init_extra_nodes(init_custom_nodes=False, init_api_nodes=False))
core_available = set(nodes.NODE_CLASS_MAPPINGS)

missing = required - core_available
node_types = manifest.get("node_types", {})
repos = manifest.get("repos", {})

unresolved = sorted(n for n in missing if n not in node_types)
if unresolved:
    sys.exit(
        "No custom-nodes-manifest.json entry for: " + ", ".join(unresolved) +
        "\nRun: python scripts/register-workflow-nodes.py --comfy-root " + comfy_root +
        " --write " + workflow_path
    )

needed_repo_keys = sorted({node_types[n] for n in missing})
todo_repos = sorted(k for k in needed_repo_keys if repos.get(k, {}).get("git_url", "").startswith("TODO"))
if todo_repos:
    sys.exit(
        "custom-nodes-manifest.json has a TODO repo for: " + ", ".join(todo_repos) +
        f"\nFill in the real git_url/revision in {manifest_path} first."
    )

for key in needed_repo_keys:
    entry = repos[key]
    print(f"{key}\t{entry['git_url']}\t{entry['revision']}")
PY
)"

while IFS=$'\t' read -r repo_key git_url revision; do
  [[ -z "${repo_key}" ]] && continue
  repo_dir="${COMFY_ROOT}/custom_nodes/${repo_key}"
  echo "==> Installing custom node repo: ${repo_key} @ ${revision}"
  if [[ ! -d "${repo_dir}/.git" ]]; then
    git clone "${git_url}" "${repo_dir}"
  else
    git -C "${repo_dir}" fetch origin
  fi
  git -C "${repo_dir}" checkout "${revision}"
  if [[ -f "${repo_dir}/requirements.txt" ]]; then
    "${PYTHON}" -m pip install -r "${repo_dir}/requirements.txt"
  fi
  if [[ "${repo_key}" == "ComfyUI-LTXVideo" ]]; then
    # The LTXVideo pyramid code imports `pad`, which was removed from newer
    # Kornia releases. Pin this after the node requirements, which otherwise
    # upgrades Kornia back to the latest incompatible version. Applied
    # whenever LTXVideo is a resolved dependency for this workflow, not
    # only on a fresh clone, so an already-installed repo still ends up
    # with a compatible Kornia version.
    "${PYTHON}" -m pip install --force-reinstall --no-deps "kornia==0.7.4"
  fi
done <<< "${REQUIRED_REPOS}"

echo "==> Creating model directories"
mkdir -p \
  "${COMFY_ROOT}/models/checkpoints" \
  "${COMFY_ROOT}/models/text_encoders" \
  "${COMFY_ROOT}/models/loras" \
  "${COMFY_ROOT}/models/vae" \
  "${COMFY_ROOT}/models/diffusion_models"

# Remove the incompatible/stale encoder variant. ComfyUI may otherwise keep
# selecting it instead of the public fp4 encoder used by these workflows.
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

echo "==> Resolving models required by $(basename "${WORKFLOW_PATH}")"
# Prints "filename<TAB>subdir<TAB>url" for every model file the selected
# workflow references, looked up in models-manifest.json. Fails loudly if a
# referenced file has no manifest entry (or the entry still has a TODO url),
# instead of silently skipping the download - run
# scripts/register-workflow-models.py to scaffold missing entries.
MODEL_LINES="$("${PYTHON}" - "${WORKFLOW_PATH}" "${PROJECT_ROOT}/models-manifest.json" <<'PY'
import json
import sys

workflow_path, manifest_path = sys.argv[1], sys.argv[2]
workflow = json.loads(open(workflow_path, encoding="utf-8").read())
manifest = json.loads(open(manifest_path, encoding="utf-8").read())

refs = set()
for node in workflow.get("nodes", []):
    for value in node.get("widgets_values", []):
        if isinstance(value, str) and value.endswith((".safetensors", ".ckpt", ".pt", ".pth")):
            refs.add(value)

missing = sorted(r for r in refs if r not in manifest)
if missing:
    sys.exit(
        "No manifest entry for: " + ", ".join(missing) +
        "\nRun: python scripts/register-workflow-models.py " + workflow_path
    )

todo = sorted(r for r in refs if manifest[r].get("url", "").startswith("TODO"))
if todo:
    sys.exit(
        "models-manifest.json has a TODO url for: " + ", ".join(todo) +
        f"\nFill in the real download url(s) in {manifest_path} first."
    )

for ref in sorted(refs):
    entry = manifest[ref]
    print(f"{ref}\t{entry['subdir']}\t{entry['url']}")
PY
)"

while IFS=$'\t' read -r name subdir url; do
  [[ -z "${name}" ]] && continue
  mkdir -p "${COMFY_ROOT}/models/${subdir}"
  download "${url}" "${COMFY_ROOT}/models/${subdir}/${name}"
done <<< "${MODEL_LINES}"

echo "==> Verifying downloaded files"
while IFS=$'\t' read -r name subdir url; do
  [[ -z "${name}" ]] && continue
  ls -lh "${COMFY_ROOT}/models/${subdir}/${name}"
done <<< "${MODEL_LINES}"

echo "==> Installing workflows"
mkdir -p "${COMFY_ROOT}/user/default/workflows"
cp "${PROJECT_ROOT}/workflows/"*.json "${COMFY_ROOT}/user/default/workflows/"

echo "==> Verifying the selected workflow has no missing node classes"
"${PYTHON}" - "${COMFY_ROOT}" "${WORKFLOW_PATH}" <<'PY'
import asyncio
import json
import pathlib
import sys

comfy_root = pathlib.Path(sys.argv[1])
workflow_path = pathlib.Path(sys.argv[2])
workflow = json.loads(workflow_path.read_text(encoding="utf-8"))

sys.path.insert(0, str(comfy_root))
import nodes
asyncio.run(nodes.init_extra_nodes(init_custom_nodes=True, init_api_nodes=False))
available = set(nodes.NODE_CLASS_MAPPINGS)

required = {node["type"] for node in workflow.get("nodes", [])}
missing = sorted(required - available)
if missing:
    raise SystemExit("Missing node classes: " + ", ".join(missing))
print(f"OK {workflow_path.name}: {len(required)} node types available")
PY

if [[ "${NO_START}" == "--no-start" ]]; then
  echo
  echo "Setup complete. Skipping ComfyUI start (--no-start)."
  exit 0
fi

echo
echo "Setup complete. Starting ComfyUI on port ${COMFY_PORT:-8188}."
exec "${PYTHON}" "${COMFY_ROOT}/main.py" \
  --listen 0.0.0.0 \
  --port "${COMFY_PORT:-8188}"
