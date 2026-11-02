#!/usr/bin/env python3
"""Check design-document index membership and local relative links."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

_LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
_CHAPTER = re.compile(r"^[0-9]{2}-.+\.md$")


def _local_target(raw: str) -> str | None:
    target = raw.strip().strip("<>").split()[0] if raw.strip() else ""
    if not target:
        return None
    if target.startswith(("#", "http://", "https://", "mailto:")):
        return None
    return target.split("#", 1)[0]


def check_docs_policy(root: Path) -> list[str]:
    design = root / "design"
    readme = design / "README.md"
    errors: list[str] = []
    if not readme.is_file():
        return [f"missing {readme.relative_to(root).as_posix()}"]

    index_text = readme.read_text(encoding="utf-8")
    chapters = sorted(
        path.name for path in design.iterdir() if path.is_file() and _CHAPTER.match(path.name)
    )
    for name in chapters:
        needle = f"](./{name})"
        if needle not in index_text and f"]({name})" not in index_text:
            errors.append(f"design/README.md does not link to {name}")

    markdown_files = {readme}
    markdown_files.update(design.rglob("*.md"))
    for markdown in sorted(markdown_files):
        if markdown.suffix != ".md":
            continue
        text = markdown.read_text(encoding="utf-8")
        for match in _LINK.finditer(text):
            relative = _local_target(match.group(1))
            if relative is None or not relative:
                continue
            resolved = (markdown.parent / relative).resolve()
            try:
                resolved.relative_to(root.resolve())
            except ValueError:
                errors.append(
                    f"{markdown.relative_to(root).as_posix()} links outside the repository: {relative}"
                )
                continue
            if not resolved.exists():
                errors.append(
                    f"{markdown.relative_to(root).as_posix()} broken local link: {relative}"
                )
    return errors


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=".")
    args = parser.parse_args(argv)
    root = Path(args.root).resolve()
    errors = check_docs_policy(root)
    if errors:
        for error in errors:
            print(error, file=sys.stderr)
        return 1
    print("docs-policy: design index and local links are present")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
