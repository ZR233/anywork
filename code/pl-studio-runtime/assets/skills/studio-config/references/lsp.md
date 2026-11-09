# Configure and verify LSP

Language servers supply semantic operations such as hover, definitions, references
and diagnostics. Start language development by checking the current workspace's
LSP status. Configuration and initialization are separate: a valid TOML file or a
successful executable version check does not prove the server can answer queries.

## Location and execution side

Create one document at:

```text
<actual execution workspace>/.anywork/lsp/<server-id>.toml
```

The workspace is the current Thread's checkout or worktree, not necessarily the
project's original directory. Use the latest host facts. SSH reads this directory
on the remote machine and starts the executable there. A program installed on
the Studio host cannot serve a remote project through a local path.

Each file has its own `schema_version = 1` and an `id` matching the filename.
IDs contain ASCII letters, digits, `-`, `_` or `.`, excluding `.` and `..`.
The main `config.toml` no longer accepts `[lsp.servers]`.
Local defaults may live at `<studio-home>/lsp/host/<server-id>.toml`; a workspace
document with the same ID replaces the entire default. SSH does not inherit Host
defaults. Prefer workspace documents for project-specific configuration.

## Rust example

Check the execution-side installation and the project's toolchain before writing
the configuration. If command execution is authorized, use that platform's
commands to locate `rust-analyzer` and inspect its version. A rustup proxy may
exist even when the selected toolchain lacks the component. Report that error;
install a component only within the user's authorization. The product does not
automatically install language servers.

```toml
# .anywork/lsp/rust-analyzer.toml
schema_version = 1
id = "rust-analyzer"
command = "rust-analyzer"
language_ids = ["rust"]
extensions = [".rs"]
detection = ["Cargo.toml"]

[initialization_options]
checkOnSave = false

[initialization_options.files]
watcher = "client"

[settings.rust-analyzer.files]
watcher = "client"
```

`checkOnSave = false` avoids an unsolicited check build in a navigation-only
session. Change it when the project's intended server behavior requires checks.
Use the server's official documentation for all settings:
[rust-analyzer configuration](https://rust-analyzer.github.io/book/configuration.html).
Its initialization options use the server's own names and nesting.

`command` is an execution-side PATH program or absolute executable path.
`args` is an array of separate arguments, not a shell command.
`env` adds environment entries for the server. No shell expansion is performed.
`{workspaceRoot}` can be used in commands, arguments, environment and nested
configuration strings to refer to the actual absolute execution workspace.
Do not put `~`, shell substitutions or a compound shell command in `command`.

Required fields are `schema_version`, `id`, `command` and nonempty `language_ids`.
Optional fields include `display_name`, `args`, `env`, `extensions`, `detection`,
`operations`, `initialization_options` and `settings`. Empty detection matches any
workspace; otherwise use root filenames or supported single-segment patterns.
Avoid two servers claiming the same language in one workspace.

## Initialization options and settings

These are different LSP mechanisms:

- `initialization_options` goes in the initialize request. Restarting the affected
  server is required to apply a change.
- `settings` supplies `workspace/didChangeConfiguration` and the responses to
  `workspace/configuration`. Use nested sections named as the server expects.

Do not assume another editor's setting names are automatically translated.
For example, `settings.rust-analyzer` is the section queried by rust-analyzer;
its initialization options do not need that prefix.
The distinction follows the
[LSP specification](https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/)
and is also explained by [Zed](https://zed.dev/docs/configuring-languages).

## Project-specific auxiliary files in session scratch

Use the latest `studio.session-files` fact for this Thread's execution-side
`scratch` directory. It already tells the model where temporary files belong.
Create server-specific response files, generated project descriptions or other
temporary configuration there when the server supports them. Reference the
actual path explicitly in its documented argument, environment variable or
initialization setting.

For rust-analyzer, a project using a generated `rust-project.json` can place that
file in current scratch and set `initialization_options.linkedProjects` to an
array containing its execution-side absolute path. Generate a valid project
description according to rust-analyzer's official contract; do not use a dummy
file to suppress Cargo errors. A normal Cargo project generally needs no such
file. Temporary toolchain/build settings can instead be passed through the
documented `cargo.extraEnv` settings.

Never substitute a local scratch path for a remote one. Never inspect another
Thread's directory. Do not save credentials in TOML or auxiliary files. Session
archival removes temporary files, so a configuration that references them needs
those files prepared again before reuse. Shared persistent project settings
belong in the project's intended location.

## Observe, verify and recover

Use the independently available, read-only `lsp_status` tool to inspect the
current workspace. It does not start a server or wait for initialization.
Configuration changes trigger background loading and initialization; the GUI
also provides explicit reload. Servers initialize concurrently, so one slow or
failed server does not block the others or the conversation.

Inspect the configuration source, lifecycle phase and error:

- No configuration: check the actual execution workspace and filename.
- Loading/probing/starting/initializing: initialization is still in progress;
  continue independent work rather than repeatedly restarting.
- Disabled: check detection files and the project root.
- Failed: fix the reported TOML, executable, environment or handshake problem.
  Preserve the original error and unrelated working configurations.
- Ready: discover the available semantic tools and verify a meaningful query.
- Stopped or exited: inspect the error and reload after fixing its cause.

Only initialized, live servers contribute semantic tools. If none are healthy,
semantic tools are absent while status remains available. A healthy server in a
mixed configuration remains usable. A failed LSP must not prevent normal
messages, filesystem tools or command execution.

After configuring Rust, request hover over a known function call or definition
navigation to a symbol in the sample source. Confirm the returned symbol/type or
location matches the project. A tool being listed, an empty query result or a
server process being present alone is insufficient. When repairing a failure,
observe recovery and retry the semantic query in the same Thread; creating a new
conversation should not be necessary.
