#!/usr/bin/env python3
"""Fault-sensitive checks for the Cargo boundary guard, without invoking Cargo."""

from __future__ import annotations

import unittest
from pathlib import Path

from check_tool_boundaries import boundary_errors


class ToolBoundaryTest(unittest.TestCase):
    root = Path("/workspace/code/tools")

    def metadata(self, edges, names=None):
        names = names or {}
        identities = set(edges)
        identities.update(target for targets in edges.values() for target in targets)
        paths = {
            identity: self.root
            / ("support/shared" if identity == "support" else identity)
            / "Cargo.toml"
            for identity in identities
        }
        return {
            "packages": [
                {
                    "id": identity,
                    "name": names.get(identity, f"pl-tool-{identity}"),
                    "manifest_path": str(path),
                }
                for identity, path in paths.items()
            ],
            "workspace_members": ["tool", "support"],
            "resolve": {
                "nodes": [
                    {
                        "id": identity,
                        "deps": [{"pkg": target} for target in edges.get(identity, [])],
                    }
                    for identity in identities
                ]
            },
        }

    def errors(self, metadata, manifests=None):
        return boundary_errors(
            metadata, manifests or [self.root / "tool/Cargo.toml"], self.root
        )

    def test_independent_shared_support_is_allowed(self):
        graph = self.metadata({"tool": ["support"], "support": ["api"]})
        self.assertEqual(self.errors(graph), [])

    def test_transitive_host_dependency_reports_the_chain(self):
        graph = self.metadata(
            {"tool": ["support"], "support": ["host"]}, {"host": "pl-core"}
        )
        self.assertEqual(
            self.errors(graph),
            ["forbidden tool dependency: pl-tool-tool -> pl-tool-support -> pl-core"],
        )

    def test_dependency_kinds_are_not_filtered(self):
        graph = self.metadata({"tool": ["host"]}, {"host": "pl-model"})
        graph["resolve"]["nodes"] = [
            {
                "id": "tool",
                "deps": [
                    {
                        "pkg": "host",
                        "dep_kinds": [
                            {"kind": "build", "target": "cfg(windows)"},
                            {"kind": "dev", "target": None},
                        ],
                    }
                ],
            },
            {"id": "host", "deps": []},
        ]
        self.assertIn("pl-model", self.errors(graph)[0])

    def test_families_cannot_depend_on_another_complete_family(self):
        graph = self.metadata({"tool": ["other"]})
        graph["workspace_members"].append("other")
        errors = self.errors(
            graph, [self.root / "tool/Cargo.toml", self.root / "other/Cargo.toml"]
        )
        self.assertEqual(
            errors, ["forbidden tool dependency: pl-tool-tool -> pl-tool-other"]
        )

    def test_shared_support_cannot_hide_a_complete_family_dependency(self):
        graph = self.metadata({"tool": ["support"], "support": ["other"]})
        graph["workspace_members"].append("other")
        errors = self.errors(
            graph,
            [
                self.root / "tool/Cargo.toml",
                self.root / "support/shared/Cargo.toml",
                self.root / "other/Cargo.toml",
            ],
        )
        self.assertIn(
            "forbidden tool dependency: pl-tool-tool -> pl-tool-support -> pl-tool-other",
            errors,
        )

    def test_no_discovered_packages_is_not_success(self):
        graph = self.metadata({"tool": []})
        self.assertEqual(
            boundary_errors(graph, [], self.root),
            ["no independent tool packages were checked"],
        )

    def test_missing_member_and_missing_graph_fail_closed(self):
        graph = self.metadata({"tool": []})
        graph["workspace_members"] = []
        self.assertTrue(self.errors(graph))
        graph["resolve"] = None
        self.assertIn("omitted", self.errors(graph)[0])

    def test_cycles_do_not_hide_a_forbidden_dependency(self):
        graph = self.metadata(
            {"tool": ["support"], "support": ["tool", "host"]},
            {"host": "pl-studio-runtime"},
        )
        self.assertTrue(any("pl-studio-runtime" in error for error in self.errors(graph)))


if __name__ == "__main__":
    unittest.main()
