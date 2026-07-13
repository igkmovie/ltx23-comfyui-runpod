#!/usr/bin/env python3
"""Report (and optionally scaffold) custom-nodes-manifest.json entries for
the node classes a workflow references.

Usage:
    python scripts/register-workflow-nodes.py [workflow.json ...] [--comfy-root PATH] [--write]

With no workflow arguments, scans every workflows/*.json in the repo.

Without --comfy-root (or the COMFY_ROOT env var), this script cannot tell
which required node classes are already provided by ComfyUI core, so it
only reports classes missing from custom-nodes-manifest.json's node_types
map as "unclassified - verify whether this is core or needs a custom node
repo registered". It never guesses core vs custom.

With --comfy-root pointing at a real ComfyUI checkout, it imports ComfyUI's
core-only node registry (init_custom_nodes=False) to get the authoritative
core-available set, then only reports classes that are both missing from
core AND missing from the manifest.

By default this script never writes anything - it only reports. Pass
--write to append TODO-* stub entries for newly-seen unclassified/missing
classes to custom-nodes-manifest.json (existing entries are never
modified). bootstrap-runpod.sh refuses to clone a repo whose manifest key
still starts with "TODO-", so a stub must be filled in by hand before it
can be used.
"""
import argparse
import asyncio
import json
import os
import pathlib
import sys

REPO_ROOT = pathlib.Path(__file__).resolve().parent.parent
MANIFEST_PATH = REPO_ROOT / "custom-nodes-manifest.json"
TODO_PREFIX = "TODO-"


def extract_node_types(workflow: dict) -> set[str]:
    return {node["type"] for node in workflow.get("nodes", []) if "type" in node}


def core_available_node_types(comfy_root: pathlib.Path) -> set[str]:
    sys.path.insert(0, str(comfy_root))
    import nodes  # type: ignore

    asyncio.run(nodes.init_extra_nodes(init_custom_nodes=False, init_api_nodes=False))
    return set(nodes.NODE_CLASS_MAPPINGS)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("workflows", nargs="*", help="Workflow JSON path(s); default: all workflows/*.json")
    parser.add_argument("--comfy-root", default=os.environ.get("COMFY_ROOT"),
                         help="Path to a ComfyUI checkout, used to determine which node classes are core-provided")
    parser.add_argument("--write", action="store_true",
                         help="Append TODO stub entries to custom-nodes-manifest.json for unclassified classes")
    args = parser.parse_args()

    workflow_paths = [pathlib.Path(p) for p in args.workflows] or sorted((REPO_ROOT / "workflows").glob("*.json"))

    manifest = {"repos": {}, "node_types": {}}
    if MANIFEST_PATH.exists():
        manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))

    all_required: set[str] = set()
    for workflow_path in workflow_paths:
        workflow = json.loads(workflow_path.read_text(encoding="utf-8"))
        all_required |= extract_node_types(workflow)

    core_available: set[str] | None = None
    if args.comfy_root:
        comfy_root = pathlib.Path(args.comfy_root)
        try:
            core_available = core_available_node_types(comfy_root)
        except Exception as exc:  # noqa: BLE001
            print(f"Warning: could not import ComfyUI at {comfy_root} ({exc}); "
                  f"falling back to manifest-only classification.")

    already_registered = set(manifest.get("node_types", {}))

    if core_available is not None:
        candidates = all_required - core_available
        print(f"Core-available classes: {len(core_available)} (from {comfy_root})")
    else:
        candidates = all_required
        print("No --comfy-root/COMFY_ROOT given; cannot distinguish core-provided classes. "
              "Reporting every class not already in the manifest.")

    unclassified = sorted(candidates - already_registered)

    if not unclassified:
        print(f"No unclassified node classes across {len(workflow_paths)} workflow file(s).")
    else:
        print(f"{len(unclassified)} class(es) need attention:")
        for name in unclassified:
            print(f"  - {name}")

    if unclassified and args.write:
        repos = manifest.setdefault("repos", {})
        node_types = manifest.setdefault("node_types", {})
        for name in unclassified:
            repo_key = f"{TODO_PREFIX}{name}"
            repos[repo_key] = {"git_url": "TODO", "revision": "TODO"}
            node_types[name] = repo_key
        MANIFEST_PATH.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        print(f"\nWrote {len(unclassified)} stub repo/node_types entr{'y' if len(unclassified) == 1 else 'ies'} "
              f"to {MANIFEST_PATH}. Fill in the real git_url/revision for each TODO-* repo.")

    todo_keys = sorted(
        name for name, repo_key in manifest.get("node_types", {}).items()
        if manifest.get("repos", {}).get(repo_key, {}).get("git_url", "").startswith("TODO")
    )
    if todo_keys:
        print("\nEntries still needing a real repo (git_url/revision):")
        for name in todo_keys:
            print(f"  - {name}")
        return 1
    return 0 if not unclassified else 1


if __name__ == "__main__":
    raise SystemExit(main())
