---
name: lsp-code-navigation
description: Prepare and verify language servers for a project's languages, or use semantic queries for definitions, inferred types, references, implementations, call relationships and diagnostics. Covers project loading, query discovery and initialization or query failures.
category: development
---

# Semantic code navigation with LSP

Use this workflow for code questions as well as edits, without waiting for the
user to mention LSP. Language skills provide project/build context; this skill
owns the common workflow, while `studio-config` owns anywork's configuration format.

A completed setup needs a loadable project, an initialized server, discovered
query tools and a meaningful semantic result. **After the server becomes ready,
discover tools using the ID fragment `lsp` again**, even if an earlier discovery
already exposed `lsp_status`. Searches for operation names such as `definition`,
`hover` or `diagnostics` do not check whether the LSP query tool is available.

Prefer semantic queries when the answer depends on symbol resolution, inferred
types or cross-file relationships. Choose the useful steps below rather than
turning every file read into a setup exercise. An empty server list means setup
may be needed, not that the language is unsupported. If preparation or a query is
blocked, continue independent investigation and distinguish source-based inference
from semantic evidence; successful tool use is not a prerequisite for every answer.

## 1. Check context and permission

Identify the actual execution workspace, target files, language projects and
relevant SDK/build context. A language project may be nested inside the workspace;
the absence of a manifest at the workspace root does not mean there is no project.
Trace the target file to its manifest and workspace membership rather than assuming
the shell directory, repository root and language project root are interchangeable.
Check native LSP status and reuse a suitable healthy server. Readiness alone does
not establish that it analyzes the intended project or conditional/generated code.

Before starting a missing server, verify that the language's project tooling can
resolve the target project's structure. Prefer the lowest-cost official metadata
or project-inspection command for the installed toolchain, using the project's
existing SDK and build context. Check its exit status and whether the target file
belongs to the resolved project; reading a manifest is not a successful load.
An enclosing workspace, missing dependency resolution or generated inputs can
prevent analysis even when the server starts. Repair an authorized preparation
gap before initialization; do not conceal it with server tuning or a dummy
manifest. Standalone files may be valid without a manifest. This check does not
require a full build, dependency upgrade or execution of untrusted project code.

Before declaring sources absent, check the execution root, manifest paths and
search filters or ignore rules. An empty default file listing can exclude an
ignored nested project even when its manifest and sources exist. Verify expected
paths with scoped reads; do not alter ignore rules or scan parent workspaces.

An empty status is a preparation step, not proof that LSP is unavailable. In an
authorized writable workspace, a code question or “do not change business code”
does not itself prohibit local tooling configuration. An explicit no-write
request or a read-only role does: reuse existing services and report the gap.
Do not invent such a restriction from your own “read-only analysis” commentary.
Do not install programs, execute untrusted project code or expand access without
authorization.

For shared prerequisites, let the root or a tasked writable preparation owner
handle minimal, reversible setup within existing authorization. Planning alone
does not forbid that preparation, but it does not authorize business changes,
real user settings or credentials; requested configuration deliverables retain
their approval boundary. Read-only explorers reuse the environment and query their
own symbols, reporting missing setup to the parent rather than writing it.
Hand off the actual workspace, config source, analysis context, observed results
and remaining gaps, not just "ready". Independent worktrees need their own scope
check; shared checkouts do not share session scratch.

## 2. Prepare only what the task needs

If configuration is missing, failed or mismatched, load `studio-config`, then
load its `references/lsp.md` support file through the skill reader. The main
skill is only an index; do not guess its installed path or search a user's home.

Verify the executable on the execution side. Consult that server's official
manual and installed-version help for startup, configuration namespaces, option
semantics and lifecycle. Derive parameters from the task and project rather than
copying a universal preset. In particular, analysis platform/features, package
roots, generated-code support, background checks and resource use should reflect
actual development needs. Account for build scripts or other code execution
that server initialization may trigger. Do not claim options were applied without
a corresponding status/query check.

For every non-default option, verify its exact name, nesting and value type in
official documentation. Do not add optional tuning from memory; omit unnecessary
options when their contract is uncertain. Readiness does not validate arbitrary
server-specific fields or prove that an optional setting took effect.

When setup is useful and authorized, use the verified executable and options to
write the missing workspace server document in the current anywork format.
Observe initialization and discover the query interface. If package resolution
is needed, use the project's authorized preparation command; a missing generated
package file alone does not establish that preparation is impossible.

Preserve unrelated configuration. Follow
current workspace/session paths, especially over SSH; local executables cannot
serve a remote project through a substituted host path. Keep temporary auxiliary
files in the current session's scratch and reference them explicitly.

## 3. Discover the semantic query interface

Configuration, initialization, tool discovery and a meaningful result are
separate evidence. While a server initializes, continue independent reading
rather than repeatedly restarting it.

Inspect the capability/query schemas returned by the post-readiness `lsp`
discovery. Definition, hover and references may be operations within one query
tool. Use the actual advertised operation, path, position and result-limit fields;
native and MCP tools may use different coordinates.

The current model request's catalog may lag behind server readiness. If discovery
still shows only status, finish useful independent work and rediscover on a later
model step with bounded attempts. Do not restart a healthy server just to refresh
tool names or substitute an SDK command for the semantic query.

## 4. Query and check the answer

Use a relevant definition, hover/type, references, implementation or supported
call query. Text search can locate candidates and surrounding code, but does not
resolve imports, inferred types, trait dispatch or conditional compilation.
For position queries, read the target file's relevant lines and place the cursor
inside the intended identifier, or use a symbol query's returned source position.
Keep each file's path and own line numbers together: numbering across concatenated
files is not a position in any one file. Follow the advertised character encoding
and coordinate base rather than counting output prefixes or bytes. Recompute the
position after an edit; a cursor on a neighboring module or import can produce a
valid response about the wrong symbol.

Check the returned declaration and type against the intended symbol. A jump from
an import path to a library is not evidence that a function call resolved. For an
invalid position or unexpected empty result, reread that file's local context and
correct the position before blaming initialization or repeating the request.
An empty result, server process or listed tools alone do not prove success.

For example, a cross-file method query should reach its declaring source and
identify its signature/type. A conditional Rust call should resolve to the branch
selected by the intended platform/features. Do not count textual inference as a
semantic result, or navigation as proof of runtime behavior or passing tests.

When demonstrating diagnostic refresh, query the original error before repairing
the probe, then observe its disappearance after the edit. If query tools remain
unavailable, preserve the probe for later verification rather than fixing it
without the requested before/after evidence.

Initial indexing can produce transient empty results or `ContentModified` even
without a source edit. Preserve the response, wait for progress through bounded
retries, and inspect the eventual result; do not rewrite source to provoke an
update. For persistent failure, inspect the actual configuration, initialization
or query error and fix its cause within scope. If a ready server repeatedly gives
empty results at a verified position, inspect project loading and membership
rather than treating readiness as proof that indexing will eventually succeed.
Retry after correcting a concrete cause; reload only the affected server if that
server's lifecycle requires it. Keep ordinary development available.

Report useful semantic results and relevant locations when obtained. Otherwise
explain the observed permission, executable, project, configuration or query gap,
and what the available source evidence does establish. Do not claim unavailability
from an empty initial catalog, or overstate unverified branches and platforms.
Distinguish first-attempt success from recovery after retries or repairs. A useful
setup report identifies the execution side, project, configuration source and
meaningful query result, with any remaining gap; do not report only "configured".
