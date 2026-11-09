#!/usr/bin/env python3
"""Validate independent tools against Cargo's resolved, all-feature dependency graph."""

from __future__ import annotations

import json
import subprocess
import sys
from collections import deque
from pathlib import Path


def _forbidden(name: str) -> bool:
    return name in {"pl-tool", "pl-core", "pl-model", "pl-protocol"} or name.startswith(
        ("pl-studio-", "flutter_rust_bridge")
    )


def boundary_errors(metadata: dict, manifests: list[Path], tools_root: Path) -> list[str]:
    """Inspect every dependency kind and target; never infer independence from imports."""
    packages = {package["id"]: package for package in metadata["packages"]}
    by_manifest = {
        Path(package["manifest_path"]).resolve(): identity
        for identity, package in packages.items()
    }
    resolve = metadata.get("resolve")
    if resolve is None:
        return ["Cargo metadata omitted the resolved dependency graph"]
    nodes = {node["id"]: node for node in resolve["nodes"]}
    members = set(metadata["workspace_members"])
    errors = []
    roots = []
    for manifest in manifests:
        identity = by_manifest.get(manifest.resolve())
        if identity is None or identity not in members:
            errors.append(f"independent package is not a workspace member: {manifest}")
        else:
            roots.append(identity)
    if not roots:
        errors.append("no independent tool packages were checked")
        return errors

    # A family contains all of its tool modules. Cross-family reuse may only go
    # through narrow libraries under support, never another complete family.
    family_ids = {
        identity
        for identity in roots
        if Path(packages[identity]["manifest_path"]).resolve().relative_to(tools_root).parts[0]
        != "support"
    }
    for root in roots:
        queue = deque([(root, [packages[root]["name"]])])
        visited = set()
        while queue:
            identity, chain = queue.popleft()
            if identity in visited:
                continue
            visited.add(identity)
            package = packages.get(identity)
            node = nodes.get(identity)
            if package is None or node is None:
                errors.append(f"incomplete Cargo dependency graph: {' -> '.join(chain)}")
                continue
            if _forbidden(package["name"]) or (identity != root and identity in family_ids):
                errors.append(f"forbidden tool dependency: {' -> '.join(chain)}")
                continue
            for dependency in node["deps"]:
                target = dependency["pkg"]
                target_package = packages.get(target)
                label = target_package["name"] if target_package else target
                queue.append((target, [*chain, label]))
    return errors


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    tools_root = root / "code" / "tools"
    manifests = sorted(
        manifest
        for manifest in tools_root.rglob("Cargo.toml")
        if not {"fixtures", "target"}.intersection(manifest.relative_to(tools_root).parts)
    )
    # Do not use --no-deps, --filter-platform, or a default-feature-only graph:
    # optional, build, test and platform-specific paths are part of the boundary.
    result = subprocess.run(
        ["cargo", "metadata", "--locked", "--all-features", "--format-version", "1"],
        cwd=root,
        stdout=subprocess.PIPE,
        check=True,
    )
    errors = boundary_errors(json.loads(result.stdout), manifests, tools_root)
    for error in errors:
        print(error, file=sys.stderr)
    if errors:
        return 1
    families = sum(
        manifest.relative_to(tools_root).parts[0] != "support" for manifest in manifests
    )
    print(
        f"Validated dependency closures for {families} independent tool families "
        f"and {len(manifests) - families} shared support packages"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
