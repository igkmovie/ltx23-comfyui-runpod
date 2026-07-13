#!/usr/bin/env python3
"""Scaffold models-manifest.json entries for the models a workflow references.

Usage:
    python scripts/register-workflow-models.py [workflow.json ...]

With no arguments, scans every workflows/*.json in the repo. For each model
filename referenced by a workflow (any widgets_values string ending in
.safetensors/.ckpt/.pt/.pth) that is not already in models-manifest.json,
adds a stub entry with a guessed subdir and a TODO url placeholder. Existing
entries are never modified. bootstrap-runpod.sh refuses to download a file
whose manifest url is still a TODO placeholder, so the stub must be filled
in by hand before it can be used.
"""
import json
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "models-manifest.json"
MODEL_SUFFIXES = (".safetensors", ".ckpt", ".pt", ".pth")
TODO_URL = "TODO: fill in download URL"

SUBDIR_HINTS = (
    ("vae", "vae"),
    ("clip", "text_encoders"),
    ("text_encoder", "text_encoders"),
    ("gemma", "text_encoders"),
    ("lora", "loras"),
)


def guess_subdir(filename: str) -> str:
    lower = filename.lower()
    for needle, subdir in SUBDIR_HINTS:
        if needle in lower:
            return subdir
    return "checkpoints"


def extract_model_refs(workflow: dict) -> set[str]:
    refs = set()
    for node in workflow.get("nodes", []):
        for value in node.get("widgets_values", []):
            if isinstance(value, str) and value.endswith(MODEL_SUFFIXES):
                refs.add(value)
    return refs


def main() -> int:
    args = sys.argv[1:]
    if args:
        workflow_paths = [pathlib.Path(a) for a in args]
    else:
        workflow_paths = sorted((REPO_ROOT / "workflows").glob("*.json"))

    manifest = {}
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    all_refs: set[str] = set()
    for workflow_path in workflow_paths:
        workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
        all_refs |= extract_model_refs(workflow)

    new_entries = sorted(ref for ref in all_refs if ref not in manifest)
    for ref in new_entries:
        manifest[ref] = {"subdir": guess_subdir(ref), "url": TODO_URL}

    if new_entries:
        MANIFEST_PATH.write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
        )
        print(f"Added {len(new_entries)} stub entr{'y' if len(new_entries) == 1 else 'ies'} to {MANIFEST_PATH}:")
        for ref in new_entries:
            print(f"  - {ref} (subdir: {manifest[ref]['subdir']}) -- fill in the url")
    else:
        print(f"No new models found across {len(workflow_paths)} workflow file(s); manifest already up to date.")

    todo = sorted(name for name, entry in manifest.items() if entry.get("url") == TODO_URL)
    if todo:
        print("\nEntries still needing a real download url:")
        for name in todo:
            print(f"  - {name}")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
