---
name: dart-development
description: Use when understanding, navigating, explaining, writing, debugging or reviewing Dart code, including Flutter projects. Includes code questions without edits, definitions, inferred types, references and cross-file call relationships.
category: development
---

# Dart project development

Use this entry point for Dart code questions as well as implementation. Preserve
the project's chosen architecture, SDK constraints and command entry points.

## Establish the package context

- Read the relevant pubspec, analysis options and package/workspace structure.
  Distinguish a pure Dart package from a Flutter application and identify the
  package containing the queried source.
- Locate the actual execution-side SDK and version. A Flutter project normally
  uses Flutter's bundled Dart SDK; do not silently switch SDKs or upgrade
  dependencies. Run project commands from the package/project, not the SDK
  installation directory. Respect repository wrappers and generated-file rules.
- Check dependency resolution when imports cannot be resolved. Use existing
  lockfiles and the project's dependency-preparation entry point; do not edit
  generated package configuration or add source stubs to hide missing packages.
  In a monorepo, confirm analysis covers the intended package.

## Understand the code

Load `lsp-code-navigation` and follow its shared preparation and query workflow,
including for explanation-only tasks. Supply the SDK and package context above.
Select the official language server's invocation and options from the installed
SDK's help and [official LSP documentation](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md),
not a fixed command or parameter list from this skill.

Static code navigation does not require launching a Flutter application. Native
LSP and Dart/Flutter MCP are distinct integrations: use MCP when runtime errors,
hot reload or UI interaction require it, not as proof that native LSP was set up.

## Implement and verify

Follow existing async/error handling, nullability and ownership conventions.
Prefer the platform and project's existing components, and consult official API
contracts before integrating dependencies. Use relevant Dart/Flutter specialty
skills when available without assuming they are installed or loading all of them.

Validate changes with the smallest sufficient project analysis/test entry.
Use widget/runtime tools when that behavior is affected; do not apply unrelated
workspace-wide fixes or regenerate unrelated code. Report source locations,
actual evidence and uncovered behavior; navigation alone does not prove runtime
correctness or passing tests.
