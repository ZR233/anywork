# Language-server configuration

This reference owns anywork's document format and loading behavior. Server
executables, arguments and server-specific options are not universal presets:
select them for the task and installed server version using its official manual.
A valid document does not by itself prove that the server can answer queries.

For code investigation, a writable preparation owner may set up the required
project server during planning under the existing authorization; business plan
approval is not a blanket prerequisite for this setup. Read-only explorers reuse
the verified service or hand the specific setup gap to the parent. Preserve role,
path, installation and project-execution restrictions, and do not modify real
user settings or credentials without authorization. If configuring the server is
itself the task's deliverable, its implementation approval still applies.

## Location and execution side

Create one document at:

```text
<actual execution workspace>/.anywork/lsp/<server-id>.toml
```

Use the current Thread's actual checkout/worktree. SSH reads this directory on
the remote machine and starts the executable there; a program installed on the
Studio host cannot serve a remote project through a local path.

Each file has `schema_version = 1` and an `id` matching its filename. IDs contain
ASCII letters, digits, `-`, `_` or `.`, excluding `.` and `..`. Local defaults may
live at `<studio-home>/lsp/host/<server-id>.toml`; a workspace document with the
same ID replaces the entire default. SSH does not inherit Host defaults. Prefer
workspace documents for project-specific configuration.

## Document structure

The following is a **shape template**, not a runnable server preset. Replace the
executable and language ID with verified values and supply arguments/options
from the selected server's current official contract:

```toml
# .anywork/lsp/project-language.toml
schema_version = 1
id = "project-language"
command = "<verified execution-side executable>"
language_ids = ["<server language ID>"]
# args = [...]                 # Separate arguments, when needed by this server.
# extensions = [...]           # Source extensions claimed by this server.
# detection = [...]            # Actual root markers, if detection is desired.
# initialization_options and settings use the server's own nested schema.
```

`command` is an execution-side PATH program or absolute executable path, not a
shell command. No shell expansion is performed. `{workspaceRoot}` can be used
in commands, arguments, environment and nested configuration strings to refer
to the actual absolute execution workspace. Do not use `~`, shell substitutions
or compound commands. For stdio, use an executable that preserves the server's
protocol stream rather than a wrapper that adds stdout messages.

Required fields are `schema_version`, `id`, `command` and nonempty `language_ids`.
Unknown fields are rejected. There is no `cwd`, `enabled` or `transport` field;
execution uses the actual workspace and command driver.

| Optional field | Type/default |
| --- | --- |
| `display_name` | string; omitted uses `id` |
| `args` | string array, `[]` |
| `env` | string-to-string table, `{}` |
| `extensions` | string array, `[]`; extensions normalize to lowercase with a leading dot |
| `detection` | string array, `[]`; empty matches any workspace, otherwise root filenames or single-segment globs |
| `operations` | string array; omitted enables all supported operations below |
| `initialization_options`, `settings` | nested TOML values; omitted means no supplied value |

Operation names are `goToDefinition`, `findReferences`, `hover`, `documentSymbol`,
`workspaceSymbol`, `goToImplementation`, `prepareCallHierarchy`, `incomingCalls`,
`outgoingCalls`, `diagnostics`. Server capabilities still determine availability.
Multiple servers may claim the same language. Select one with the query's
`serverId`; without an explicit selection, multiple matching servers produce an
ambiguity error with candidates rather than a guessed priority.

Detection is a workspace eligibility filter, not a language-project locator, and
is not recursive. For nested projects, first locate the target files' actual
manifests and workspace membership. Keep server documents at the execution
workspace's configuration location; placing them in an arbitrary package does not
change this Thread's configuration scope. If a language marker exists only below
the workspace root, do not use that filename as a root-only filter. Omit detection
or choose a real root marker, then check how the server includes those projects
using its own documented discovery or configuration. Starting a server with no
filter does not prove project coverage. Do not invent a detection path to a nested
package or copy another project's paths and settings.

## Select server parameters from development needs

Inspect the project's SDK/toolchain, manifests, existing configuration and
intended build/run command before choosing options. Consult documentation matching
the installed version, including help/version output where supported. Preserve
intentional project settings rather than replacing them with generic defaults.

Useful official sources include:

- [rust-analyzer configuration](https://rust-analyzer.github.io/book/configuration.html)
  and [installation](https://rust-analyzer.github.io/book/installation.html).
  Select analysis platform, feature/default-feature set and Cargo target kinds
  from the requested build context. Analysis options, checker options and build
  output directories serve different purposes. Evaluate generated code, build
  scripts and procedural macros when needed; startup may invoke Cargo or execute
  project code even if continuous checking is disabled. A rustup proxy does not
  prove the selected toolchain contains the component. Do not default to enabling
  every feature or fabricate cfg/project descriptions to hide errors.
- [Dart analysis server LSP documentation](https://github.com/dart-lang/sdk/blob/main/pkg/analysis_server/tool/lsp_spec/README.md).
  Use the project's actual Dart SDK (normally Flutter's bundled SDK for Flutter),
  derive invocation/options from that SDK's help and documentation, and verify
  package resolution. Do not run project commands inside the SDK installation or
  edit generated package configuration. Native LSP does not require a Flutter app
  launch and has separate configuration/state from Dart MCP.

These are sources for decisions, not fixed parameter lists. The product does not
automatically install servers. Install components only within authorization.

## Initialization options and settings

These are separate LSP mechanisms:

- `initialization_options` goes in the initialize request. Changing it requires
  restarting the affected server; configuration reload handles that lifecycle.
- `settings` supplies `workspace/didChangeConfiguration` and responses to
  `workspace/configuration`. Use the nested section names the server requests.

Do not assume editor setting names are automatically translated. Derive both
namespaces from the server's official contract. If the same choice is supplied
through both mechanisms, keep the values consistent. Follow the
[LSP specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
for their protocol meanings, not an unrelated editor's file format.

## Project-specific auxiliary files

Use the latest session fact for this Thread's execution-side scratch directory.
When a server supports response files, generated project descriptions or temporary
build configuration, place task-specific files there and reference the actual
path through the server's documented argument/environment/initialization option.
A normal project should use its existing manifest rather than a dummy auxiliary
file made to suppress load errors.

Never substitute local paths for remote ones or inspect another Thread's scratch.
Do not put credentials in documents or auxiliary files. Session archival can
remove temporary files, so configurations referring to them need preparation
again before reuse. Shared persistent settings belong in the project's intended
location.

## Reload and verify configuration

An active agent holds a lease on its actual execution directory. Agents using the
same endpoint and directory share servers; closing one agent does not stop the
others. Releasing the last lease immediately starts server reclamation, without
an idle timer. An ordinary turn ending does not close an active agent.
Project browsing and Settings do not keep servers alive or start them; an explicit
probe holds only a temporary lease and releases it when the probe completes.

Configuration changes in a leased directory trigger background loading and
initialization. File tools notify the registry directly; completed command and
stdin tool results also cause the active Thread to check its configuration, so
documents written by shell scripts do not require another turn or an unrelated
service update. Unchanged documents do not restart healthy servers. The started
items menu observes this Thread's server rows, including loading and failure
states; opening it does not start servers. The GUI also provides explicit reload. Servers initialize
concurrently. The read-only status
operation reports published state; it does not scan, start or wait for a server.

Check the reported configuration source, phase and error. Detection mismatch is
different from an executable or handshake failure. A changed document restarts
only affected members; an unchanged healthy member should not be restarted to
refresh tools. After fixing an external cause such as a missing executable, an
explicit reload can retry a failed member even when the document is unchanged.

The final configuration check is an actual semantic query in the intended project
and build context, with a meaningful location/type result. Server process presence,
valid TOML, readiness alone or an empty query result is insufficient. Preserve
failures and unrelated working configurations; configuration failure must not
prevent ordinary messages, filesystem tools or authorized commands.

For a diagnostic check after editing, specify the intended `serverId` or
`languageId` and `filePath`. This synchronizes the execution-side disk file before
reading diagnostics. Changed open files send the negotiated change and save
notifications, including saved text only when the server requests it. Diagnostics
are published asynchronously: use bounded observation to verify that the original
error disappears after a real fix. Sending a save notification does not itself
prove a clean result; unchanged queries do not trigger another save.
