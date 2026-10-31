#!/usr/bin/env python3
"""Hash the portable environment inputs, not source, locks, docs, or CI."""

import hashlib
from pathlib import Path


def image_key(root: Path) -> str:
    paths = [
        "rust-toolchain.toml",
        "docker/linux/Dockerfile",
        "docker/linux/Dockerfile.dockerignore",
        "docker/linux/versions.env",
    ]
    # Keep host orchestration/key logic in the identity too. Tests are not inputs.
    paths.extend(
        path.relative_to(root).as_posix()
        for path in (root / "docker/linux/scripts").iterdir()
        if path.is_file()
        and path.suffix in {".sh", ".py"}
        and not path.name.startswith("test_")
    )
    digest = hashlib.sha256()
    for relative in sorted(paths):
        name = relative.encode("utf-8")
        content = (root / relative).read_bytes()
        digest.update(len(name).to_bytes(8, "big"))
        digest.update(name)
        digest.update(len(content).to_bytes(8, "big"))
        digest.update(content)
    return digest.hexdigest()


if __name__ == "__main__":
    print(image_key(Path(__file__).resolve().parents[3]))
