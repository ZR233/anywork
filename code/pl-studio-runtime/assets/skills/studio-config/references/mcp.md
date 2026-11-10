# MCP configuration

MCP connects external tool servers to each active Thread. Configuration belongs to
the Studio host, even when a server executes over SSH. It is not a section of
`config.toml` and not an editor's `mcpServers` JSON object.

## Paths, identity and execution

| Scope | Document path on the Studio host | Execution |
| --- | --- | --- |
| Host | `<studio-home>/mcp/host/<server-key>.toml` | Host process/network |
| SSH override | `<studio-home>/mcp/ssh/<ssh-key>/<server-key>.toml` | Selected SSH server process/network |

`server-key` is lowercase hexadecimal SHA-256 of the UTF-8 server `id`, without a
newline. `ssh-key` is the same hash of the exact SSH alias. IDs contain ASCII
letters, digits, `_` and `-`. Display names are not path keys. For existing entries,
use the actual document reference from the MCP catalog. Creating through Settings
generates the canonical path; when editing files directly, compute the hash using
the platform's standard SHA-256 implementation, not a guessed filename.

SSH inherits Host entries. A same-ID SSH document completely replaces the Host
entry; it does not merge fields. An inherited Host server still runs on the Host,
not on SSH. A `disabled` SSH document blocks inheritance. Removing that override
restores inheritance. Host has no `disabled` document kind.

Each document is UTF-8 TOML with root `schema_version = 1`, `id`, and `kind`.
Unknown fields and mixed transport fields are rejected, including when disabled.

## Custom stdio server

This is the complete minimal Dart example when `dart` is a directly executable
program on the execution-side PATH:

```toml
schema_version = 1
id = "dart"
kind = "server"
transport = "stdio"
command = "dart"
args = ["mcp-server"]
```

`transport` is required in the document. `command` must be nonblank. These fields
are optional:

| Field | Type and default | Meaning |
| --- | --- | --- |
| `enabled` | boolean, `true` | Desired enablement |
| `args` | string array, `[]` | Separate arguments, not a shell command |
| `env` | string-to-string table, `{}` | Additional process environment |
| `cwd` | nonblank string, omitted | Process working directory |
| `startup_timeout_secs` | positive integer, `8` | Connection and tool discovery timeout |
| `tool_timeout_secs` | positive integer, `120` | Individual tool/resource request timeout |
| `enabled_tools` | string array, omitted | Omitted allows all tools; `[]` allows none |
| `disabled_tools` | string array, `[]` | Deny list takes precedence over allow list |

For example, append top-level `cwd = '/work/my-app'` before any table, and put
environment entries under `[env]`. Do not add HTTP fields to a stdio document.
The process uses argv; shell substitutions and `~` are not automatically expanded.
Do not assume LSP's `{workspaceRoot}` substitution also exists for MCP.

Omitted `cwd` uses the Thread workspace for Host-local or SSH-override stdio.
Inherited Host stdio in an SSH Thread uses the Host base directory. Host relative
paths resolve against that base. SSH override relative paths resolve against the
remote workspace using POSIX separators; an absolute POSIX path can be supplied
directly. Prefer omitting `cwd` for a server intended to follow each local Thread's
workspace. For a monorepo, register the actual Dart package roots separately.

## Dart MCP setup and verification

Use the official [Dart and Flutter MCP server](https://docs.flutter.dev/ai/get-started),
started with `dart mcp-server`. Locate the actual installed SDK on the execution
side and inspect its version and `mcp-server --help` before choosing extra flags.
On Windows Flutter's PATH entry may be `dart.bat`; select the real SDK executable,
typically `<flutter-sdk>/bin/cache/dart-sdk/bin/dart.exe`. A Windows path can be
written as `command = 'C:\SDK\flutter\bin\cache\dart-sdk\bin\dart.exe'`.
That is a path pattern, not a path to copy without checking the machine.

Do not start the stdio server through a Cargo wrapper that prints logs to stdout.
Do not run project analysis in the SDK installation directory. `cwd` is a process
directory, not a substitute for the server's project-root registration.

After the document is loaded, discover the actual Dart MCP tools and their schemas.
Register the requested package/workspace with the server's root-management tool
using its required file URI shape, then perform a meaningful project operation
(for example analysis of a known Dart source file). Use current returned schemas,
not hard-coded tool prefixes or stale argument shapes. Successful initialization,
tool discovery and a successful project operation are separate evidence.

## Streamable HTTP server

```toml
schema_version = 1
id = "documentation"
kind = "server"
transport = "streamableHttp"
url = "https://example.com/mcp"
bearer_token_env_var = "DOCUMENTATION_MCP_TOKEN"

[headers]
Accept = "application/json, text/event-stream"
```

Replace the illustrative URL with the server's documented endpoint. `url` must be
a valid HTTP or HTTPS URL. Optional `headers` defaults to `{}`; the token environment
variable is optional. Common enablement, timeout and tool filters are the same as
stdio. Do not add `command`, `args`, `env` or `cwd`. Keep secrets out of TOML;
the configured token environment variable must be available where the connection
executes. HTTP servers do not use a stdio subprocess.

## Built-in and disabled documents

```toml
schema_version = 1
id = "zhipu_search"
kind = "builtin"
builtin_id = "zhipu_search"
enabled = true
```

`id` must equal `builtin_id`. Current reserved IDs are `zhipu_search`,
`zhipu_reader`, `zhipu_zread`, and `zhipu_vision`; custom servers cannot use them.
Built-ins accept only identity, schema, kind, `enabled` (default `true`) and
optional `cwd`. Only the stdio `zhipu_vision` accepts `cwd`; HTTP built-ins do not.
Endpoint/command/credential fields are product-owned. A usable credential comes
from the first `zhipu-coding-plan` account in stable account-ID order; another
template or a matching endpoint is not a credential substitute.

To block a Host entry in a particular SSH scope, use this complete document at
that SSH scope's same-ID canonical path:

```toml
schema_version = 1
id = "dart"
kind = "disabled"
```

It accepts no additional fields. To disable a Host custom server, keep its valid
server document and set `enabled = false` instead.

## Apply, inspect and repair

Settings document creation/update validates and publishes the catalog, then
reconciles affected open Threads. Direct filesystem edits require explicit reload
of the corresponding MCP catalog in Settings; file creation alone does not publish
it. The product API is `reload_mcp_catalog`, not necessarily a model-exposed tool.
If the current tool inventory has no reload operation, state the required Settings
reload; do not claim a new tool is usable before it appears. Restarting Studio is
not a repair for malformed configuration.

The Settings catalog describes desired configuration, not connection health.
Inspect the target Thread's MCP state and discovered tools; connections belong to
Threads. Reconnect the affected server after fixing an executable/environment or
handshake error. Keep errors and other working documents intact. A successful
standalone protocol probe can diagnose the server, but does not prove Studio loaded
the file or that the Thread can call it.
