---
name: rust-development
description: Use when understanding, navigating, explaining, writing, debugging or reviewing Rust code in a Cargo project. Includes code questions without edits, definitions, references, call relationships, target platforms and features.
category: development
---

# Rust project development

Use this entry point for Rust code questions as well as implementation. Follow
project instructions and command entry points; do not wait for the user to
mention development tools.

## Establish the build context

- Read the relevant Cargo manifest, workspace membership, toolchain and Cargo
  configuration, plus the task's build/run instructions. Identify the package and
  lib/bin/test being discussed; inspect only the necessary files.
- Determine the intended platform and enabled features, including whether default
  features apply. The host platform is not necessarily the product target. Use
  the documented deployment/build context; ask only when an unresolved choice
  changes the answer. Never default to all features.
- Distinguish the platform triple, Cargo target kinds (lib/bin/test/example), and
  build output directory. They answer different questions. Conditional code must
  be analyzed under the requested combination, not an arbitrary host default.

## Understand the code

Load `lsp-code-navigation` and follow its shared preparation and query workflow,
including for explanation-only tasks. Supply the build context above when
selecting rust-analyzer configuration. Derive server options from its installed
version and [official manual](https://rust-analyzer.github.io/book/configuration.html),
not a fixed option list from this skill. Querying one feature branch does not
prove behavior in another.

For a monorepo, confirm that the intended Cargo project is analyzed. Account for
generated code, build scripts and procedural macros when relevant: server setup
may execute project code or invoke Cargo even if no check was requested. Respect
project trust and execution authorization; do not fabricate project descriptions
or cfg values to conceal an incomplete environment.

## Implement and verify

Follow ownership, invariants, error propagation and affected callers rather than
introducing parallel abstractions. Prefer standard libraries and existing project
components; consult official API contracts before integrating dependencies.
Use relevant quality/testing skills when available, without assuming every
specialty is installed or loading them all for a small question.

Choose checks for the changed behavior using the same toolchain, platform and
feature selection as the analysis. Preserve lockfiles and repository build
entry points. Report source locations, actual evidence and inactive/unverified
branches; semantic navigation is not a replacement for compilation or tests.
