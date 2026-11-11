#!/usr/bin/env python3
"""docs-policy fails on a missing chapter link or broken relative path."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from pr_quality_docs_policy import check_docs_policy  # noqa: E402


class DocsPolicyTest(unittest.TestCase):
    def test_missing_index_entry_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            design = root / "design"
            design.mkdir()
            (design / "README.md").write_text("# index\n", encoding="utf-8")
            (design / "01-overview.md").write_text("hello\n", encoding="utf-8")
            errors = check_docs_policy(root)
            self.assertTrue(any("01-overview.md" in item for item in errors))

    def test_broken_relative_link_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            design = root / "design"
            design.mkdir()
            (design / "README.md").write_text(
                "- [overview](./01-overview.md)\n", encoding="utf-8"
            )
            (design / "01-overview.md").write_text(
                "See [missing](./no-such.md)\n", encoding="utf-8"
            )
            errors = check_docs_policy(root)
            self.assertTrue(any("no-such.md" in item for item in errors))

if __name__ == "__main__":
    unittest.main()
