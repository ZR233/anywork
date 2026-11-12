---
name: lsp-code-navigation
description: Use for semantic code understanding and navigation, including definitions, inferred types, references, implementations, call relationships and diagnostics. Includes preparing a missing language server for code questions, discovering query tools and recovering initialization or query failures.
category: development
---

# Semantic code navigation with LSP

Use this workflow for code questions as well as edits, without waiting for the
user to mention LSP. Language skills provide project/build context; this skill
owns the common workflow, while `studio-config` owns anywork's configuration format.

**Complete the workflow before answering:** obtain a relevant semantic result,
or report an observed blocking failure/explicit permission restriction. An empty
server list or absence of query tools **before configuration** is expected, not
a reason to skip setup. Do not replace authorized setup with a text-only answer.

## 1. Check context and permission

Identify the actual execution workspace, language, project roots, installed
SDK/toolchain and the build context relevant to the question. Check the native
LSP status and reuse a suitable healthy server. Confirm existing options match
the task before relying on conditional or generated code.

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

Planning is not a blanket ban on preparation. Within existing authorization and
write permissions, the root or an explicitly tasked preparation executor may
configure the minimal, reversible project tooling needed to investigate code
before the business implementation plan is approved. This is not permission to
implement business changes or edit real user settings or credentials. When
environment configuration is itself the requested deliverable, its implementation
approval still applies.

For shared prerequisites, one writable preparation owner can configure and
verify the service before independent explorers use it. Read-only explorers
reuse a suitable service and query their own symbols; they report missing setup
to the parent rather than writing configuration or treating their role's
restriction as a planning-wide ban. Hand off the execution workspace, config
source, analysis context, meaningful query result and remaining blockers.
Independent worktrees need their own scope check; shared checkouts do not share
session scratch. Continue unrelated investigation while preparation is pending.

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

Once the executable and required invocation/options are known, **write the
missing workspace server document**, using the current anywork format. Then
observe initialization and proceed to discovery below. If package resolution is
needed, use the project's authorized preparation command; a missing generated
package file alone does not establish that preparation is impossible.

Preserve unrelated configuration. Follow
current workspace/session paths, especially over SSH; local executables cannot
serve a remote project through a substituted host path. Keep temporary auxiliary
files in the current session's scratch and reference them explicitly.

## 3. Discover the semantic query interface

Configuration, initialization, tool discovery and a meaningful result are
separate evidence. While a server initializes, continue independent reading
rather than repeatedly restarting it.

After readiness, discover tools by the LSP family ID fragment `lsp`, then inspect
the returned capability/query schemas. Discovery matches tool IDs, not operation
names: definition, hover and references may be operations within one query tool.
An empty search for `definition`, `hover`, `rust` or `dart` does not establish that
queries are unavailable. Use the actual advertised operation, path, position and
result-limit fields; native and MCP tools may use different coordinates.

The current model request's catalog may lag behind server readiness. If discovery
still shows only status, finish useful independent work and rediscover on a later
model step with bounded attempts. Do not restart a healthy server just to refresh
tool names or substitute an SDK command for the semantic query.

## 4. Query and check the answer

Use a relevant definition, hover/type, references, implementation or supported
call query. Text search can locate candidates and surrounding code, but does not
resolve imports, inferred types, trait dispatch or conditional compilation.
Check the returned source location and symbol/type against the question's context;
empty results, a server process or listed tools alone do not prove success.

For example, a cross-file method query should reach its declaring source and
identify its signature/type. A conditional Rust call should resolve to the branch
selected by the intended platform/features. Do not count textual inference as a
semantic result, or navigation as proof of runtime behavior or passing tests.

Initial indexing can produce transient empty results or `ContentModified` even
without a source edit. Preserve the response, wait for progress through bounded
retries, and inspect the eventual result; do not rewrite source to provoke an
update. For persistent failure, inspect the actual configuration, initialization
or query error and fix its cause within scope. Keep ordinary development available.

Before finishing, obtain a meaningful semantic result or identify the concrete
permission, executable, configuration or query obstacle. Do not stop at “not
configured” or the skill index merely because the code is short. Report what was
queried, the relevant locations and any remaining uncertainty without overstating
unverified branches or platforms.
