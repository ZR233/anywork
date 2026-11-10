# Main configuration

`<studio-home>/config.toml` is UTF-8 TOML with `schema_version = 32`. A missing
file uses in-memory defaults; an invalid existing file is an error. Use Settings
to create accounts from templates and preserve their provider-specific metadata.
External edits require explicit settings reload; Settings saves validate and write
atomically. A successful save is not proof of provider, usage API or MCP health.

## Accounts and model routes

This minimal API-account example requires a real credential supplied through the
environment. Do not replace an existing file wholesale with this example:

```toml
schema_version = 32

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

[mode_model_routes."mode.simple"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
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

Both built-in Mode routes are required. A route contains `account_id`, `model_id`
and optional `effort`, which must be supported by that model. Custom Modes inherit
`mode.simple` unless their full ID has an explicit route. Existing Threads retain
their own route; changing these defaults does not replace their frozen selection.

`[models.routes.<system-child-id>]` optionally overrides a declared built-in child
Agent's route. Omission inherits the complete `mode.simple` route; an invalid
explicit route does not fall back. Root Agent identities are not child routes.
`disabled_system_agents = ["<child-id>"]` is a root-level array, default `[]`; get
actual child IDs from the current catalog instead of inventing them.

Catalogs use either `source = "bundled"` plus `catalog = "<catalog-id>"`, or
`source = "explicit"` with required `models` array (which may be empty). Manual
entries use `additional_models` for bundled catalogs and `models` for explicit
catalogs; use the model editor for their full declarations. Both accept per-model
`connection_overrides` and `auto_compact_overrides`, defaulting to empty maps.
Online observations and prices are runtime-owned,
not settings to copy from another account. An explicit empty catalog can exist,
but cannot satisfy an executable model route.

`[models.accounts.<id>.model_enabled_overrides]` maps exact model IDs to booleans.
An absent key means automatic; explicit `true` cannot create an unknown model or
bypass capability/credential validation. Removing an override restores automatic
selection. Model IDs and metadata are account-local.

`[models.accounts.<id>.catalog.auto_compact_overrides]` maps model IDs to positive
integer thresholds. Omission uses the model layer's effective automatic threshold;
it is not universally 90% of the context window. Remove only the desired key to
restore automatic behavior. Observe any backend adjustment and keep unknown
capacity unknown.

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

`[deepseek_web_search]` has only `enabled` and `fetch_enabled`, both default `true`.
They independently enable Search and Fetch; it has no result-count or OpenAI
location/context fields. Search providers and generic MCP tools can coexist;
there is no exclusive search-backend selector. Available accounts and credentials
still determine whether their tools can be registered.

## ACP accounts

```toml
[acp.accounts.antigravity]
name = "Antigravity"
provider = "antigravity"
```

These are separate from Native `[models.accounts]`. Both fields are required;
`name` is nonblank, at most 200 bytes, with no control characters. Current ACP
provider is `antigravity`. Server executable versions and argv are managed by the
product; `program` and `args` are not accepted here. ACP accounts are not Native
model-route candidates. Use Settings for login and availability.
