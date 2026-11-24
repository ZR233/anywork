# Main configuration

`<studio-home>/config.toml` is UTF-8 TOML with `schema_version = 34`. A missing
file uses in-memory defaults in interactive hosts; `anywk exec` requires an existing
file and fails strictly. An invalid existing file is an error. Use Settings
to create accounts from templates and preserve their provider-specific metadata.
External edits require explicit settings reload; Settings saves validate and write
atomically. A successful save is not proof of provider, usage API or MCP health.

## Desktop diagnostic logging

Desktop diagnostics read the Studio host's startup environment, not the SSH
workspace or an ACP definition's `env`. A valid `ANYWORK_LOG_LEVEL` (`error`,
`warn`, `info`, `debug`, `trace`) takes precedence over `RUST_LOG`; otherwise
`RUST_LOG` accepts tracing EnvFilter directives. The default is `warn`. Restart
the isolated application to apply startup logging changes; settings reload does
not replace its process-wide subscriber.

`pl_studio_runtime::acp_host_call_evidence=trace` records the original Host MCP
domain result with its bound caller and host call ID in the existing log. It is
disabled at the default level. A global `trace` level also enables this target and
may record complete arguments and results, as may protocol-library TRACE logs.
Use payload tracing only for explicitly authorized, disposable synthetic-data
acceptance processes; do not enable it for everyday conversations or upload raw
logs. To select a narrow target, leave `ANYWORK_LOG_LEVEL` unset and use a scoped
`RUST_LOG` directive in that process's launch environment. This is not an ACP/MCP
configuration key, a business result store, a recovery mechanism or a peer ACK.

## Noninteractive CLI execution

`anywk exec` requires explicit `--studio-home`, `--cwd`, `--account`, `--model`
and `--prompt-file`. Prepare an existing valid native `config.toml`; CLI startup
never creates defaults, resets invalid configuration or resumes startup recovery.
It uses only the nonempty environment value named by the native account's
`bearer_token_env`, without accessing the system credential store. ChatGPT/OAuth,
interactive login and protected credential migration are unsupported. Compatible
accounts may omit authentication according to the native protocol rule.

```sh
anywk exec --studio-home /runs/profile --cwd /workspace/task \
  --account benchmark --model vendor/model --prompt-file /runs/prompt.txt \
  --no-default-user-skills --skill-dir /opt/evaluation/skills
```

All relative paths resolve once against the process startup cwd; the task cwd is
passed separately. The CLI does not change HOME/USERPROFILE or initialize Git.
`--prompt-file -` reads UTF-8 from stdin to EOF. Optional `--reasoning-effort` uses
the selected model's native validation; `--mode` defaults to `mode.auto`.
`--max-model-steps` tightens only the root input's budget, not the whole tree.

`--no-default-user-skills` only removes the implicit user source.
`--skill-dir` repeats to append read-only collection roots after configured
`skills.external_dirs`, in argument order; it does not append `.agents/skills` or
grant write permission. Normalized duplicate argument paths keep the first.
Explicitly adding the default user path still enables it as External. Missing or
unreadable explicit directories fail, including later rediscovery. Project,
System, configured External and existing enable/disable/platform rules remain.
These options are process-local: `SkillSearchOptions`, `include_default_user_dir`
and `additional_dirs` are not accepted TOML keys.

Use explicit model catalogs and existing capability settings for an isolated
evaluation profile. Keep unrelated MCP/model-discovery activity disabled and do
not put enabled bots in the evaluation home. CLI diagnostics use stderr; stdout
contains only the final assistant text after shutdown. Optional `--output-dir`
writes a version-3 native run archive (`run.json`, `events.jsonl`, `result.json`
and content-addressed originals). Use a fresh or empty non-symlink directory;
failed export is an explicit failure. Unknown usage/cost stay null.

Native desktop bundles include `bin/anywk` (`bin/anywk.exe` on Windows;
`Contents/Resources/bin/anywk` inside the macOS app). Linux package installation
provides `/usr/bin/anywk`; the Windows user installer offers a PATH task.
Harbor is an optional local Linux consumer, never installed into the project
Docker image or run by CI. Its profile renderer consumes this same native
schema and requires explicit catalogs, environment-only credentials and isolated
homes. Do not invent benchmark-only TOML keys. Frozen history is a separate
validated data snapshot, not an alternative configuration file.

### ACP command-line sessions

Use `anywk acp-options --studio-home <path> --cwd <path> --account <acp-id>`
to open a real ACP draft, print its declared capabilities/configuration, then
close cleanly without sending a prompt. The existing valid `config.toml` is still
required. ACP accounts come from that home's `acp/<id>.toml`; they are not Native
model accounts. The external agent uses its own existing login, not imported tokens.

Use `anywk exec-acp` with the same three arguments, `--prompt-file <path>` (or `-`
for UTF-8 stdin), and repeated `--config <id=value>` from the actual declarations.
For example, when the server declares those exact IDs:

```sh
anywk exec-acp --studio-home /runs/profile --cwd /workspace/task \
  --account local-agy --config model=gemini-4-hydrogen \
  --config thought_level=high --prompt-file /runs/prompt.txt
```

Settings are applied in argument order and checked again before submission; invalid
or changed selections fail without a model fallback. `--no-default-user-skills` and
`--skill-dir` use the same runtime-only source policy as Native execution. The ACP
commands do not accept Native `--model`, `--mode`, effort/step budgets or v2 exports.
The business session resolves eligible Host MCP permission requests automatically.
If a permission request still requires user confirmation, the CLI rejects it and
exits with code 3. Output is written only after clean, drained shutdown. Unpackaged
execution requires the matching `pl-studio-mcp` on PATH, using the existing external
asset source.

Local and SSH ACP instances expose enabled host workspace and skill tools through
`anywork_` names, using the same source and permission owners as ordinary sessions.
LSP uses the actual execution workspace and shared language-service lease. The
external agent's own local tools are not a sandboxed replacement for host tools.
ACP `anywork_skill_manage` takes the complete original operation under `input`,
for example `{"input":{"action":"delete","name":"example"}}`. Its schema is
projected from the complete author schema by the common JSON-value adapter;
Native `skill_manage` remains unchanged. Text/Grammar tools use the same strict
`input` carrier with a string, including `anywork_apply_patch`; inspect the current
catalog rather than sending the old `patch` field. Object-shaped JSON tools keep
their declared arguments. The common adapter preserves schema reference scope;
generated `anywork.invalid` schema IDs are local identifiers, not network services.

## Accounts and model routes

This minimal API-account example requires a real credential supplied through the
environment. Do not replace an existing file wholesale with this example:

```toml
schema_version = 35

[models.accounts.deepseek]
template = "deepseek"
protocol = "deep_seek"
name = "DeepSeek"
authentication = "apiKey"
base_url = "https://api.deepseek.com"
bearer_token_env = "DEEPSEEK_API_KEY"

[models.accounts.deepseek.catalog]
source = "bundled"
catalog = "deepseek"

[mode_model_routes."mode.auto"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"
```

Account IDs are stable and independent of display names. Account documents require
`name`, `base_url`, `catalog` and `authentication` (`apiKey` or `chatGpt`). Preserve
the template's `protocol` and capability declarations rather than guessing them
from the URL. Optional
`bearer_token_env` names an environment variable; `http_headers` is a string map.
Use the account editor for protocol-specific capabilities, manual model definitions
and connection settings so their typed validation remains visible.

The built-in OpenAI template recommends `gpt-6.2-sol` with `medium` effort for new
selections. `gpt-6.2-astra` and `gpt-6.2-sol` both default to `medium` and support
`low`, `medium`, `high`, `xhigh` and `max`; `none` and `minimal` are not supported.
Their automatic compaction threshold follows the current model catalog. Use the account's
model settings to override that threshold; restoring automatic mode uses the
current catalog default. These recommendations do not replace saved routes, Thread model
selections or explicit compaction overrides.

The built-in Google Gemini templates use native Gemini REST (`protocol = "gemini"`,
wire API `gemini_generate_content`, credential header `x-goog-api-key`) and recommend
`gemini-4-hydrogen` (`high` effort, 1M unified context, `512,000` default automatic compaction
threshold, image/PDF/text inline input).
The bundled catalog includes the Gemini 4 series: `gemini-4-hydrogen` and `gemini-4-neon`
(default `high`; support `low`, `medium`, `high`, `xhigh`), plus `gemini-4-argon` and
`gemini-4-carbon` (default `medium`; support `low`, `medium`, `high`). All four models default
to a `512,000`-token automatic compaction threshold (overridable per account/model up to 90% of
the 1M context window, i.e. `943,718`). None of the Gemini 4 models support `minimal`, and
official Google endpoints use implicit prefix caching:

- `vertex-ai`: Google Cloud Vertex AI Gemini (`base_url = "https://aiplatform.googleapis.com/v1/publishers/google"`,
  `bearer_token_env = "GCP_API_KEY"`, catalog `"vertex-ai"`). Vertex AI API Keys do not
  expose publisher `/models` listing, so online discovery is disabled for this template.
- `gemini`: Google Gemini Developer API / AI Studio (`base_url = "https://generativelanguage.googleapis.com/v1beta"`,
  `bearer_token_env = "GEMINI_API_KEY"`, catalog `"gemini"`). Supports paginated `/models`
  online discovery (`pageSize=1000`, `pageToken`).

A compatible Responses model can declare `base.input_modalities = ["text", "file"]`,
`base.supports_parallel_tool_calls = true`, and `base.web_search_tool_type = "text"`.
Use `extra.capabilities.input` only when you need to constrain sources or MIME types.
An explicit account service policy governs which hosted tools can be used. Document
handling also depends on the endpoint: the GLM Coding Plan Responses route accepts PDFs,
and DeepSeek Flash accepts uploaded text and PDFs by file ID. Parallel tool calling is
configured in `base.supports_parallel_tool_calls` across manual, online and bundled models.

### Prompt cache hints for compatible Responses endpoints

A compatible endpoint does not inherit OpenAI service capabilities. After confirming
that it accepts `prompt_cache_key` on Responses requests, use the existing explicit
capability declaration on that account:

```toml
[models.accounts.gateway.capabilities]
source = "explicit"

[models.accounts.gateway.capabilities.prompt_cache]
dialect = "open_ai_prompt_cache_key"
```

Merge this into the account's existing declaration and preserve any other supported
explicit capabilities. `source = "explicit"` replaces template defaults; omitted
capabilities remain disabled. A custom URL can revoke template-inherited cache
support, so selecting an OpenAI model catalog alone does not enable the field.
`implicit_prefix` relies on server-side prefix matching, while `none` sends no
explicit cache hint; neither value promises that server-side caching is disabled.
The cache-key dialect currently applies to Responses, not Chat Completions.

The runtime derives independent keys for each agent's stable Thread, account and
model. Conversation and compaction share the Thread scope; title generation and
tool review use separate purposes within it. Retries and reopening the same Thread
preserve affinity. Do not put `prompt_cache_key` into a model's fixed request body
or parameter wire: conflicts with the runtime-owned field fail before network I/O.
Keys cannot replace matching prompt prefixes or isolate permissions and history.

Save through the existing main-settings flow. Subsequent model admission resolves
the current account capabilities; an already prepared request remains frozen.
Verify the actual Responses request and reported cache read/write usage. A saved
capability or a present key does not prove a cache hit or lower cost.

The built-in `mode.auto` route is required. A route contains `account_id`, `model_id`
and optional `effort`, which must be supported by that model. Custom Modes inherit
`mode.auto` unless their full ID has an explicit route. Existing Threads retain
their own route; changing these defaults does not replace their frozen selection.

`[models.routes.<system-child-id>]` optionally overrides a declared built-in child
Agent's route. Omission inherits the complete `mode.auto` route; an invalid
explicit route does not fall back. Root Agent identities are not child routes.
`disabled_system_agents = ["<child-id>"]` is a root-level array, default `[]`; get
actual child IDs from the current catalog instead of inventing them.

Catalogs use either `source = "bundled"` plus `catalog = "<catalog-id>"`, or
`source = "explicit"` with required `models` array (which may be empty). Manual
entries use `additional_models` for bundled catalogs and `models` for explicit
catalogs; use the model editor for their full declarations. Both accept per-model
`connection_overrides` and `auto_compact_overrides`, defaulting to empty maps.
Both catalog types query the compatible account’s models endpoint by default. A failed refresh preserves existing routes. A manual model requires only its API ID. For example:

```toml
[[models.accounts.gateway.catalog.models]]
[models.accounts.gateway.catalog.models.base]
slug = "my-model"
```

Optional user edits such as `base.display_name`, `base.max_context_window` and `extra.pricing` apply to this account. Leave inherited fields out of the file.

`[models.accounts.<id>.model_enabled_overrides]` maps exact model IDs to booleans.
An absent key means enabled for bundled, online and manual models. An incomplete
or empty online inventory does not automatically disable declared bundled models.
Explicit `false` remains disabled across refreshes and restarts; removing an
override restores enabled. There is no need to write `true` for every model.
Enablement cannot create an unknown model or bypass capability/credential
validation. Model IDs and metadata are account-local.

`[models.accounts.<id>.catalog.auto_compact_overrides]` maps model IDs to positive
integer thresholds up to 90% of the known maximum context (inclusive, rounded down). Removing the key restores the current automatic value across all protocols (Gemini, OpenAI, and compatible endpoints). For bundled models and members matching an account’s bundled catalog ID, the automatic default takes 90% of the provider’s `context_window` (or `max_context_window` if absent) and caps it at `auto_compact_token_limit` when supplied. For online models without a bundled counterpart and unbundled manual models, an omitted `auto_compact_token_limit` defaults to `min(256000, floor(window * 90%))` when context is declared (or stays disabled if 90% floors to `0`) and `256000` when context is unknown, without writing the fallback into `config.toml`; an explicit `auto_compact_token_limit` is still honored (capped at 90% when context is known). Unknown context and prices can be omitted.

## Credentials

API credentials saved in Settings use the protected credential store with service
`anywork` and account `account:<id>`. Stored credentials take precedence over
`bearer_token_env`. Leaving the editor credential field empty preserves the secret;
clearing it is an explicit operation. Never retrieve a secret to populate an editor
or put it in TOML, logs or screenshots.

ChatGPT subscription accounts use the product's official browser login and protected
token storage. Do not construct OAuth metadata, import another application's token
files, change authentication by relabeling billing, or copy access/refresh/ID tokens.
Reconnect through Settings. Credential transaction journals and refresh markers are
runtime-owned; preserve them on errors. Changing Studio home does not bypass pending
credential transactions. A login or model listing does not prove quota or inference.

## Runtime and delegation

| Section/key | Current type/default | Behavior |
| --- | --- | --- |
| `runtime.permission_mode` | `request-approval` (default), `auto-review`, `full-access` | Persisted desired value; this product currently enforces effective `full-access` |
| `runtime.active_skills` | string array, `[]` | Explicitly active skills |
| `runtime.openai_compaction_mode` | `remote_v2` (default), `local` | OpenAI compaction protocol selection |
| `runtime.tool_capabilities` | boolean table | `exec`, `workspace_files`, `skills`, `mcp`, `lsp`, `ask_user` default `true`; `git` defaults `false` |
| `delegation.mode` | `profile` (default), `automatic` | New-Thread child routing mode |
| `delegation.preference` | `economy`, `balanced` (default), `fast` | Automatic routing preference; retained but inactive in profile mode |

These are independent of work modes and workspace isolation. Delegation defaults
do not modify existing Threads.

## Skills and instructions

`[skills]` accepts:

| Key | Default |
| --- | --- |
| `enabled`, `auto_learn` | `true` |
| `project_dir` | `".agents/skills"` |
| `external_dirs`, `disabled` | `[]` |
| `auto_learn_min_tool_calls` | `5` |
| `system.enabled` (under `[skills.system]`) | `true` |

User skills are read-only at the platform user's `.agents/skills`, independent of
Studio home. There is no configurable `user_dir`. For skill file structure and
project instructions, see [other configuration](other-config.md).

`[instructions]` accepts `base_override`, `developer`, `user` (strings, default
empty), `project_doc_max_bytes` (default `65536`) and
`project_doc_fallback_filenames` (string array, default `[]`). `base_override`
replaces the model base instructions. `developer` names a trusted configuration
source, not a guarantee of the role sent to every provider. Project documents
remain user context. Do not edit protocol/account capabilities to force a prompt
role.

## UI and search

`[ui]` accepts `language = "system" | "zh" | "en"` (default `system`),
`follow_active_turn = true`, `compact_timeline = false`, optional integer
`sidebar_width`, and `pinned_thread_ids` / `pinned_project_ids` (default `[]`).
Pin arrays contain stable IDs. The application uses a fixed light theme.

`[web_search]` configures OpenAI standalone search: `mode` is `disabled`, `cached`
(default), `indexed` or `live`; optional `context_size` is `low`, `medium` or `high`;
`allowed_domains` defaults to `[]`. Optional `[web_search.location]` contains
string `country`, `region`, `city`, `timezone` fields, each independently optional.
OpenAI standalone search uses the current request model ID when it starts with
`gpt-`, and uses `gpt-6-luna` otherwise. The current account has priority when
it declares standalone search and has working credentials.

`[deepseek_web_search]` has only `enabled` and `fetch_enabled`, both default `true`.
They independently enable Search and Fetch; it has no result-count or OpenAI
location/context fields. Search providers and generic MCP tools can coexist;
there is no exclusive search-backend selector. Available accounts and credentials
still determine whether their tools can be registered.

## ACP accounts

```toml
# <studio-home>/acp/local-agy.toml
schema_version = 1
id = "local-agy"
display_name = "Local agy"
command = "agy"
args = ["acp"]
```

ACP definitions are separate from `config.toml` and Native `[models.accounts]`.
Only first-level files in this user directory are read. The required `id` equals
the filename stem and uses ASCII letters, digits, `-`, `_` or `.`, excluding empty,
`.` and `..`. `display_name` defaults to the ID, `enabled` to true, and args/env
to empty. A name is at most 200 bytes and contains no control characters.

Choose either a PATH program name/absolute `command` plus independent `args`, or
`template = "antigravity"` with no command/args. Both may use an explicit `[env]`
table; do not expose values in diagnostics. There is no shell, variable or `~`
expansion, configured cwd, model list or UI schema. Only the managed template
requires a verified SemVer `1.x` (`>= 1.5.2, < 2.0.0`) installation, supports
parallel startup and manual update checks against the official ACP registry, and
upgrades in-place within major version `1` (switching idle connections immediately
or deferred until active sessions close); local `agy acp` is an ordinary command
and does not inherit that brand/version requirement.

Use Settings for atomic document-CAS save/delete and explicit reload after
external edits. Startup/reload scans this directory; ordinary reads are cache-only,
and one bad file does not replace healthy definitions. Changing command/args/env or
template advances the runtime connection identity; renaming does not. Existing
business sessions on a replaced, disabled or deleted connection are closed; no
prompt or session-open request is replayed. Finish active work before changing
connection settings. The old process and pipes must settle before a replacement
can start; a display-name edit does not restart the service.

Every enabled ACP account, including ordinary commands, is prepared in the
background after Studio assembly and effective configuration changes. Invalid
commands or unavailable managed installations are blocked with a visible reason;
they are not installed automatically. Preparation does not block startup or start
interactive login. Authentication-required keeps the same instance for the user's
explicit login continuation. Authentication, supported quota queries and independent
business sessions reuse one initialized service; closing one session leaves it alive.

Transient connection/process failures reconnect only after the old instance has
been reclaimed, using 1, 2, 4, 8, 16, then at most 30 seconds between attempts.
After an initialized connection survives 60 seconds, the backoff resets. Definition,
installation, authentication, protocol-version and cleanup failures wait for user
action. No existing session or request with an unknown result is replayed. Generic
commands do not inherit Antigravity's private `/usage` capability. Connection and
authentication state are separate observations; old authentication/quota observations
are revoked when an instance fails. A successful managed installation wakes its
blocked enabled accounts.

Setting `enabled = false`, deleting the definition, replacing its connection fields,
or closing Studio cancels pending reconnects and closes the affected operations and
sessions before joining the process tree. Renaming does not restart the instance.
This behavior adds no TOML key, and reading settings never starts a process.

Local detection only checks help/version; it neither downloads nor logs in and
does not prove authentication. ACP accounts are not Native model-route candidates.
Never repair a conflict by deleting migration records, definitions or credentials.

For SSH projects, keep this same host-side definition and login. Do not install
agy or an ACP server on the SSH target, copy credentials, or add an SSH tunnel.
Host MCP exposes the ordinary session command, file and enabled Git capabilities
through the project's frozen execution binding. Existing tool capability switches
and permission checks still apply; tool availability is not a sandbox for the
external agent's own local tools. ACP uses a private host session working directory
while business tool paths refer to the real SSH workspace. Command receipts,
stdin, task wait/results and cancellation must use the original returned identity;
an accepted cancellation is not proof of remote process exit.

`runtime.tool_capabilities.exec` controls the `exec_command` / `write_stdin` command bindings. Native tools are called through Lua `exec`, which accepts `code`; shell commands use `tools.exec_command({command=...})` inside that program. Disabling command bindings still permits orchestration of other enabled tools. There is no legacy execution-mode switch.
