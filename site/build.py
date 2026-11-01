#!/usr/bin/env python3
"""Assemble and verify the static GitHub Pages bundle for anywork."""

from __future__ import annotations

import argparse
from html.parser import HTMLParser
from pathlib import Path
import re
import shutil
import struct
import sys

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"

STATIC_FILES = (
    "index.html",
    "styles.css",
    "app.js",
)

COPIED_ASSETS = (
    ("code/anywork/assets/branding/anywork-startup-cat.webp", "assets/anywork-startup-cat.webp"),
    ("code/anywork/assets/branding/anywork-startup-cat.png", "assets/anywork-startup-cat.png"),
    ("design/assets/readme-workspace.png", "assets/readme-workspace.png"),
    ("design/assets/readme-agent-evaluation.png", "assets/readme-agent-evaluation.png"),
    ("design/assets/readme-model-evaluations.png", "assets/readme-model-evaluations.png"),
    ("design/assets/readme-workflow-editor.png", "assets/readme-workflow-editor.png"),
    ("code/anywork/assets/provider-logos/openai.svg", "assets/providers/openai.svg"),
    ("code/anywork/assets/provider-logos/deepseek.svg", "assets/providers/deepseek.svg"),
    ("code/anywork/assets/provider-logos/xai.svg", "assets/providers/xai.svg"),
    ("code/anywork/assets/provider-logos/zhipu.svg", "assets/providers/zhipu.svg"),
    ("code/anywork/assets/provider-logos/mimo.svg", "assets/providers/mimo.svg"),
)

ICON_TARGETS = {
    32: "assets/favicon-32.png",
    128: "assets/app-icon-128.png",
    256: "assets/app-icon-256.png",
}


class LocalAssetCollector(HTMLParser):
    """Collect relative asset references from HTML tags."""

    def __init__(self) -> None:
        super().__init__()
        self.references: set[str] = set()

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        for attr, raw_value in attrs:
            if not raw_value:
                continue
            if attr in {"src", "href", "poster"}:
                self._record(raw_value)
            elif attr == "srcset":
                for candidate in raw_value.split(","):
                    tokens = candidate.strip().split()
                    if tokens:
                        self._record(tokens[0])

    def _record(self, url: str) -> None:
        value = url.strip()
        if not value or value.startswith(("#", "http://", "https://", "mailto:", "data:")):
            return
        clean = value.split("#", 1)[0].split("?", 1)[0]
        if clean:
            self.references.add(clean)


def extract_ico_png_frames(ico_path: Path, out_dir: Path) -> None:
    data = ico_path.read_bytes()
    if len(data) < 6:
        raise ValueError(f"Invalid ICO header: {ico_path}")
    reserved, icon_type, count = struct.unpack_from("<HHH", data, 0)
    if reserved != 0 or icon_type != 1 or count == 0:
        raise ValueError(f"Unexpected ICO directory header in {ico_path}")

    frames: dict[int, bytes] = {}
    for index in range(count):
        entry_offset = 6 + index * 16
        width_raw, height_raw, _, _, _, _, size, offset = struct.unpack_from(
            "<BBBBHHII", data, entry_offset
        )
        width = width_raw or 256
        height = height_raw or 256
        payload = data[offset : offset + size]
        if width == height and payload.startswith(PNG_SIGNATURE):
            frames[width] = payload

    for dimension, rel_dest in ICON_TARGETS.items():
        payload = frames.get(dimension)
        if payload is None:
            raise RuntimeError(
                f"Expected {dimension}x{dimension} PNG frame inside {ico_path}, found {sorted(frames)}"
            )
        target = out_dir / rel_dest
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(payload)


def verify_bundle(out_dir: Path) -> None:
    index_html = out_dir / "index.html"
    collector = LocalAssetCollector()
    collector.feed(index_html.read_text(encoding="utf-8"))

    app_js = (out_dir / "app.js").read_text(encoding="utf-8")
    for match in re.finditer(r"""["'](\./assets/[^"']+|assets/[^"']+)["']""", app_js):
        collector.references.add(match.group(1))

    missing: list[str] = []
    out_resolved = out_dir.resolve()
    for ref in sorted(collector.references):
        candidate = (out_dir / ref).resolve()
        try:
            candidate.relative_to(out_resolved)
        except ValueError:
            missing.append(f"{ref} (escapes output root)")
            continue
        if not candidate.is_file() or candidate.stat().st_size == 0:
            missing.append(ref)

    if missing:
        raise RuntimeError(f"Broken or empty local asset references: {', '.join(missing)}")


def build_site(repo_root: Path, out_dir: Path) -> None:
    site_dir = repo_root / "site"
    if out_dir.exists():
        shutil.rmtree(out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    for filename in STATIC_FILES:
        src = site_dir / filename
        if not src.is_file():
            raise FileNotFoundError(f"Missing site source file: {src}")
        shutil.copy2(src, out_dir / filename)

    for rel_src, rel_dest in COPIED_ASSETS:
        src = repo_root / rel_src
        if not src.is_file():
            raise FileNotFoundError(f"Missing repository asset: {src}")
        dest = out_dir / rel_dest
        dest.parent.mkdir(parents=True, exist_ok=True)
        if rel_dest == "assets/providers/mimo.svg":
            svg_text = src.read_text(encoding="utf-8").replace(
                'viewBox="0 0 152 132"', 'viewBox="8 56 136 20"'
            )
            dest.write_text(svg_text, encoding="utf-8")
        else:
            shutil.copy2(src, dest)

    ico_path = repo_root / "code/anywork/windows/runner/resources/app_icon.ico"
    if not ico_path.is_file():
        raise FileNotFoundError(f"Missing application icon: {ico_path}")
    extract_ico_png_frames(ico_path, out_dir)

    verify_bundle(out_dir)


def main() -> int:
    repo_root = Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--out",
        type=Path,
        default=repo_root / "target" / "pages",
        help="Destination directory for assembled GitHub Pages files",
    )
    args = parser.parse_args()
    out_dir = args.out if args.out.is_absolute() else (Path.cwd() / args.out)
    build_site(repo_root, out_dir)
    print(f"Assembled verified GitHub Pages bundle at {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
