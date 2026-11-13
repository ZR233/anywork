---
name: studio-config
description: Configure anywork accounts, model routes, MCP servers, language servers (LSP), skills, Agent Profiles and work modes. Explains current file formats, configuration paths, scope, reload and verification. Use for setup or configuration repair, including Dart MCP.
metadata:
  category: guides
---

# anywork configuration

Use the current formats below to configure anywork. Read only the reference for
the requested feature; do not copy another client's JSON configuration into anywork.
This main document is an index: load the selected support file through the skill
reader, not a guessed installation path.

ACP programs and authentication remain on the Studio host for SSH projects too.
Remote workspace tools use the ordinary session execution binding through Host MCP;
see the ACP section in the main configuration reference, not remote agent setup.

## Find the correct location

`<studio-home>` is the running application's configuration root, resolved in order:
`--studio-home <absolute path>`, `ANYWORK_HOME` (nonempty absolute path), then
the platform user's `.anywork` directory. On Windows the default is
`%USERPROFILE%\.anywork`; on Unix it is `$HOME/.anywork`.
An isolated application may use a different root. Confirm the running instance's
root before writing; the default path alone is not evidence of the active root.

For a local Thread, inspect the inherited `ANYWORK_HOME` value with the available
command tool (`$env:ANYWORK_HOME` in PowerShell); do not dump the whole environment.
Check any known launch override before using it. If necessary, inspect the running
instance's launch arguments or product settings. A remote shell's environment does
not identify the Studio host's root. Ask for the missing root only after available
local evidence cannot establish it; absence of a settings tool alone is not proof
that the path is unavailable.

`<workspace>` means this Thread's actual execution checkout/worktree. SSH workspace
paths refer to the remote machine. Studio-owned configuration and execution-side
configuration are different locations:

| Configure | Current file/location | Read next |
| --- | --- | --- |
| Native accounts, routes, runtime, skills, UI, search | `<studio-home>/config.toml`, TOML schema 33 | [Main configuration](references/main-config.md) |
| Noninteractive `anywk exec` | Explicit `--studio-home`, existing native config, environment-only credentials and runtime-only skill options | [CLI execution](references/main-config.md#noninteractive-cli-execution) |
| ACP definitions | `<studio-home>/acp/<id>.toml`, TOML schema 1 | [Main configuration](references/main-config.md#acp-accounts) |
| MCP, including Dart MCP | `<studio-home>/mcp/host/<key>.toml` or `mcp/ssh/<ssh-key>/<key>.toml`, TOML schema 1; both directories are on the Studio host | [MCP formats and setup](references/mcp.md) |
| Language servers | `<workspace>/.anywork/lsp/<id>.toml`, TOML schema 1; local defaults at `<studio-home>/lsp/host/<id>.toml` | [LSP formats and setup](references/lsp.md) |
| User child Agent Profiles | `<studio-home>/agents/<id>.toml`, TOML schema 3 | [Profiles and work modes](references/agents-and-modes.md) |
| Custom work modes | `<studio-home>/modes/<id>.json`, JSON editing document | [Profiles and work modes](references/agents-and-modes.md) |
| SSH connections, project instructions, skill files | Standard user/project locations, independent of Studio home | [Other configuration and storage](references/other-config.md) |

## Edit and verify

Planning may include minimal, reversible project tooling setup needed for
investigation, within existing authorization and write permissions. Use a
writable preparation owner when an explorer is read-only; this does not grant
business implementation, installation or real user configuration access.
If configuration itself is the requested deliverable, follow that task's
implementation approval boundary rather than relabeling it preparation.

1. Inspect the active scope and existing configuration. Prefer available product
   settings/document operations for validation and correct path generation. For a
   file edit, preserve the original and change only the requested settings.
   When the root and write scope are established, complete the authorized file edit
   even if reload is a separate unavailable operation; report that remaining step.
2. Follow the relevant reference's exact field spelling and nesting. Schema
   versions belong to individual documents; never bump a header to repair a file.
   Use TOML literal strings for Windows paths, for example `'C:\SDK\dart.exe'`,
   or escape backslashes in double-quoted strings.
3. Preserve account IDs and credential associations. Use Settings for credential
   changes; do not print secrets or copy tokens into examples, logs or skill files.
4. Apply the feature's reload mechanism. Main settings, MCP and LSP do not have
   interchangeable reload behavior. If no suitable operation is exposed to the
   current agent, report the required UI action rather than inventing a tool.
5. Confirm the canonical configuration and actual behavior. For MCP, a saved file
   is not a connection: verify discovered tools and a meaningful tool call. For
   LSP, verify initialization and a real semantic query. Preserve exact failures;
   do not report success based only on a process, a version check or your own summary.

Keep only current supported formats in this skill. Migration journals, backups,
databases and credential records are runtime-owned; do not edit or delete them to
make configuration validation pass. Historical migration details are not setup
instructions.
