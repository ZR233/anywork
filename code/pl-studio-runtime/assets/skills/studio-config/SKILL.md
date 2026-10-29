---
name: studio-config
description: Use when asked where anywork stores configuration, project/session data, temporary files, or helper transfers, or how to configure accounts, model routes, permissions, skills, MCP, LSP, UI, or web search. Covers storage ownership, TOML schema, credentials, and safe editing.
metadata:
  category: guides
---

# anywork Configuration

Use this skill when the user asks where anywork keeps its settings or wants to configure something outside the Settings page.

## Where Configuration Lives

anywork reads a single user config file:

```text
~/.anywork/config.toml          Windows: %USERPROFILE%\.anywork\config.toml
```

The home directory can be overridden, in resolution order:

1. `--studio-home <absolute path>` launch argument
2. `ANYWORK_HOME` environment variable (absolute, non-empty)
3. default `<user home>/.anywork`

The product database lives in `<home>/studio/v2/studio.sqlite`; canonical global directory indexes and product settings live in `<home>/v2/`. Call records use `<home>/v2/calls/calls.sqlite` and rolling logs under `logs/`. Project data lives in `<home>/v2/projects/<project-key>/`; each Thread keeps `history.sqlite`, `attachments.toml`, `blobs/`, and `thread-resources/` in its `sessions/<thread-key>/`. Both keys are SHA-256 digests of stable IDs, not display names or working directories. Old-version directories remain isolated. Never edit these files by hand.

`project.toml` and `session.toml` are runtime-owned identity manifests, not extra editable settings. Mutable directory summaries stay in the canonical indexes; current route, Mode, Plan, notes, and execution metadata stay in the checkpoint. Existing flat v2 sessions are moved through a resumable layout migration, not discarded. A layout-migration failure stops startup and preserves its source and journal; it never triggers the global backup-and-defaults recovery described below.

## Session Files and Helper Transfers

- Use the latest `studio.session-files` host fact for this Thread's workspace-relative `scratch/`, `artifacts/`, and command-output directory. These are under `<workspace>/.anywork/sessions/<thread-key>/`; SSH paths belong to the remote workspace, not the local home. Each child and reviewer has its own Thread directory even when sharing a checkout.
- Temporary scripts and intermediate files belong in `scratch/`; unfinished deliverables belong in `artifacts/`. Put final project files in the user's requested location and report other deliverables' actual paths. Tool-managed build and acceptance outputs keep their documented locations.
- The host session's `scratch/` is internal transfer staging, not a model-writable database directory. Remote captures are downloaded there before durable resource retention; attachments without a Thread remain in `<home>/studio/v2/attachment-drafts/`.
- Helper executables are shared remote-user assets in `$HOME/.anywork/remote-helper/<version>/<digest>/`. Upload staging is unique and beside the final executable; ordinary atomic file writes stage beside their target. Neither location is a general-purpose task scratch directory.
- Runtime pools contain non-overwriting `.gitignore` files. Do not overwrite user ignore rules, clear active scratch/history, or scan old `target/pure/` output as a cleanup shortcut. Directory write scopes, read-only roles, and SSH/worktree confinement still apply.

Feishu bots live in `<home>/v2/bots/<bot-id>/` with versioned `config.toml` and `state.sqlite`; App Secret uses the independent credential account `bot:<bot-id>` and never enters TOML or SQLite. The runtime talks to Feishu with native Rust HTTP/WebSocket/Protobuf only. Bot Threads use the same project-bound session layout described above.

## Format Rules

- TOML with snake_case keys; the current runtime accepts `schema_version = 27`. Changing the version number alone does not migrate a configuration.
- A missing file means in-memory defaults shown in Settings; nothing is written until you save.
- Known version upgrades preserve user settings and credential associations through migration. Startup migrates schema 18 to 19 by removing only `planner` from `disabled_system_agents`, then migrates 19 to 20 by copying the old `planner` route to `mode.simple` and `mode.task` before deleting it from child routes. Migration runs before recovery; a reset is never a substitute for a supported migration.
- Schema 21 to 22 migrates model declarations from `slug` to `model_id`. Schema 22 to 23 migrates `models.providers` to `models.accounts`, `preset`/`adapter` to `template`/`protocol`, and route/Profile `provider`/`model` to `account_id`/`model_id`. Account and template ID values, endpoint, headers, model overrides and user choices are preserved. Older supported versions continue through these steps; changing only the version number is invalid.
- Schema 26 to 27 converts each account's `disabled_models` into `model_enabled_overrides` entries with value `false`, removes the old field, and leaves other models automatic. It uses the normal protected backup and recoverable migration, preserving identity, credentials, routes and other overrides. Normal configuration only uses the new map.
- Main configuration, user Profiles and credential associations use a recoverable migration operation. Protected original bytes are backed up before replacement; interrupted commits resume before publishing a canonical snapshot. A supported migration failure stops initialization and preserves the source/operation, never resets data. Existing v2 model-route/Profile extensions, typed bills and call records migrate at their versioned storage boundary without activating all sessions or rewriting opaque vendor payloads.
- Unrecoverable global data corruption, unsupported versions and invalid references trigger one complete startup backup of `config.toml`, `agents/`, `v2/` and `studio/v2/` under `<home>/startup-backups/<unique-id>/original/`, followed by initialization with current defaults. The durable `startup-recovery.toml` journal resumes an interrupted recovery. The UI reports the backup location. Permission, capacity, file-lock, credential-service and internal failures stop initialization without resetting. System credentials, old-version directories, remote connection configuration and physical project/worktree directories are preserved. Individual session read failures do not reset global data.
- Explicit reload while Studio is running remains strict: it reports the invalid file instead of replacing it.
- Saving from Settings writes atomically. External file edits are not picked up automatically; use explicit reload after editing a valid current-schema file.
- Account save replies confirm the credential/configuration transaction, not MCP readiness or usage API completion. All templates use the same save path; MCP follows canonical configuration in the background and reports its own status.

## Common Sections

- `[models.accounts.<id>]` — account endpoint, template, credential reference, model catalog.
- `[mode_model_routes."<mode-id>"]` — new/root Thread default route per full Mode ID. `mode.simple` and `mode.task` are required; custom Modes inherit `mode.simple` until explicitly saved.
- `[models.routes.<system-agent-id>]` — optional explicit model override for a declared system child. Omitted entries inherit the complete `mode.simple` route; existing explicit entries remain authoritative and must resolve. Unknown IDs and root identities are rejected. Root Threads keep their route in the Thread state checkpoint instead of a global `planner` route.
- `[runtime]` — `permission_mode` (`request-approval` | `auto-review` | `full-access`), tool capabilities, active skills and MCP servers.
- `[skills]` — enable/disable, auto-learn, project/user/external skill directories, disabled skills. The default writable project directory is `.agents/skills`; explicit `project_dir` values remain unchanged. In addition to configured `user_dir`, 糊来帮 always discovers the read-only user compatibility directory at `$HOME/.agents/skills` on Linux and `%USERPROFILE%\.agents\skills` on Windows.
- `[mcp]` — custom servers under `[mcp.servers.<id>]` plus builtin server states.
- `[lsp.servers.<id>]` — command-based LSP servers outside the bundled catalog.
- `[ui]` — `follow_active_turn`, `compact_timeline`. Studio always uses its fixed light theme. The obsolete `follow_system_theme` key is ignored when reading current-schema files and omitted on the next normal save; no configuration reset is needed.
- `[web_search]` — OpenAI standalone `/alpha/search` configuration: mode, context size, allowed domains, location.
- `[deepseek_web_search]` — Two independent switches for the DeepSeek Search & Fetch tools: `enabled` (web search) and `fetch_enabled` (page fetch), both defaulting to `true`. The section, a missing key, and a missing section all mean enabled. It defines no result count, content toggle, OpenAI-specific mode, domain, location, or context option; those request details are fixed deployment constants in code.
- `[instructions]` — base override, trusted developer-source rules, user context, and project doc limits. `developer` names a configuration source, not the API role sent to every provider.

System-prompt composition belongs to Studio: it combines the selected base, frozen Agent role,
Mode, and other trusted sources in a stable order. `base_override` replaces the model base; an
absent model base uses the builtin prompt. Project documents and dynamic runtime facts keep their
user-context boundary. The model protocol layer maps the combined prompt to OpenAI Responses
`developer`, DeepSeek Responses `system`, or the selected adapter's supported role. Do not change
account settings to force a role or enable history updates merely because a model answered a probe.
Append-only prompt updates require an explicit capability for the actual wire API; DeepSeek's
Messages `in-history` declaration does not establish Responses support. Unsupported updates replace
the effective instruction prefix while ordinary conversation history remains append-only.

## Agent definitions and child Profiles

Every root and child Agent uses the same declaration, instruction assembly, and frozen-snapshot model.
Built-in declarations are typed entries in `src/agent/catalog.rs`; each instruction is Markdown under
`src/agent/prompts/*.md` and compiled into the binary with `include_str!`, so runtime does not read an
Agent resource directory. Add a declaration entry and its prompt file together. Product entry points
bind a trusted root identity. The root is not a configurable child Profile and has no global `planner`
route or user-facing role selector. `list_agent_profiles` and the Agents settings page expose only
eligible child declarations; user TOML files also define children only.

Builtin child IDs come from the embedded declaration catalog, not a fixed list in this guide. A system
child may omit `[models.routes.<agent-id>]`; when absent, its effective account, model, and effort inherit
`mode.simple` without being written back to TOML. An explicit child route takes precedence, and an
unavailable explicit route does not fall back. User child Profiles keep their explicit route in their
own TOML file. Only child Profiles can be enabled/disabled or dispatched; root identity, metadata, and
instruction text cannot grant child or root privileges.

A few sections are omitted when left at defaults (`runtime`, `instructions`, `lsp`, `ui`); a default Studio save still writes `[skills]` with `project_dir = ".agents/skills"` and `user_dir = "~/.anywork/skills"`, `[web_search]` with `mode = "cached"`, and `[deepseek_web_search]` with `enabled = true` and `fetch_enabled = true`, so do not delete them assuming they are unused.

Web search is not a single selection. Both services are resolved independently of the session, route, or current model: OpenAI standalone search uses the account's `gpt-6-sol` when its catalog has it (otherwise the account's first valid model), DeepSeek search calls the official `POST {root}/v1/tools/search` and `POST {root}/v1/tools/fetch` endpoints without resolving any model, and accounts are ordered by stable ID. Account availability depends only on capability plus a usable key; whether the current model supports function calling only decides whether that thread registers the additive tools. At runtime the OpenAI `web_search`, DeepSeek `deepseek_web_search` (`queries`, 1–4 merged queries) and `deepseek_web_fetch` (`url`), and any generic MCP tools (including Zhipu, discovered and registered through generic MCP when a valid key is available) coexist as additive tools; there is no `selected` backend and no exclusive route that hides the other tools. Only the two DeepSeek tool descriptions mention per-request billing and the fallback condition, and searches are neither ordered nor automatically fallen back across accounts. `enabled` and `fetch_enabled` gate the tools independently, and each switch only affects its own tool. A DeepSeek account instance that overrides the template's canonical base URL stops inheriting the DeepSeek standalone capability unless it explicitly declares the `deep_seek_tools_api` dialect; the pre-21 token `deep_seek_anthropic_messages` is rewritten by the configuration migration and is rejected if written by hand. This revocation is DeepSeek-only and does not change the existing OpenAI `/alpha/search` standalone inheritance for non-canonical OpenAI endpoints.

## Work modes

Custom work modes are separate JSON files, not sections in `config.toml`:

```text
~/.anywork/modes/<mode-id>.json    Windows: %USERPROFILE%\.anywork\modes\<mode-id>.json
```

The file name must match the document `id`. For example, `mode.review-flow` is stored as `mode.review-flow.json`. A document has six execution fields at the top level plus optional `editor.nodes`:

```json
{
  "id": "mode.review-flow",
  "displayName": "Review flow",
  "description": "Review one bounded change.",
  "order": 10,
  "prompt": "Follow the active review stage.",
  "workflow": {
    "title": "Review",
    "goal": "Finish the review.",
    "initialStateId": "inspect",
    "states": [
      {
        "id": "inspect",
        "title": "Inspect",
        "instructions": "Inspect the change.",
        "completionCriteria": ["Findings are recorded."],
        "kind": "atomic"
      },
      {
        "id": "done",
        "title": "Done",
        "instructions": "",
        "completionCriteria": [],
        "kind": "final"
      }
    ],
    "transitions": [
      {
        "sourceStateId": "inspect",
        "targetStateId": "done",
        "guard": "The review is complete."
      }
    ]
  },
  "editor": {
    "nodes": [
      { "stateId": "inspect", "x": 80, "y": 80 },
      { "stateId": "done", "x": 320, "y": 80 }
    ]
  }
}
```

The runtime compiles the workflow before publishing it. State and transition IDs must be unique and bounded; the initial state and every transition endpoint must exist; atomic stages need completion criteria; final stages cannot have outgoing transitions; and every stage must be reachable and able to reach a final stage. `editor.nodes` only stores finite canvas coordinates for existing state IDs. It is validated separately and never changes the workflow graph hash.

`mode.simple` and `mode.task` are built in and read-only. Saving or deleting a built-in ID is rejected; copy it to a new custom ID instead. A custom Mode inherits the `mode.simple` model route until a `[mode_model_routes."<mode-id>"]` entry is saved. Queries read the published catalog; external JSON edits require explicit reload. Reload validates every file before replacing the catalog. A malformed file, mismatched file name, unknown field, invalid layout, or compiler error rejects the whole reload and leaves the previous catalog intact. Keep the original file and report the exact validation issue rather than deleting it or bypassing validation.

## Model compaction thresholds

Each account catalog may store `auto_compact_overrides` keyed by exact model model_id. A missing key means no user override: use the model's explicit `auto_compact_token_limit` template, otherwise floor 90% of its resolved context capacity (`context_window`, falling back to `max_context_window`). Unknown capacity disables automatic compaction; never substitute zero or a guessed window. User overrides must be positive and the effective value cannot exceed the 90% safety limit. Restore default by removing only the corresponding override key; do not copy computed defaults into the configuration.

Edit a threshold directly in the account detail card's model list: valid input saves automatically, and restore default clears the override. Other account connection, credential and model-declaration edits still use their editor's Save/Cancel draft. A successful configuration reply does not change an in-flight model request; new bindings use it at their next safe refresh boundary.

## Credentials

Tokens never live in `config.toml`. Saving from Settings clears any inline token and stores it in the system credential store (service `anywork`, account `account:<id>`). Bot App Secrets use the same service with account `bot:<bot-id>` and the Preserve/Replace/Clear transaction; a missing system keyring keeps a process-only lease marked `sessionOnly`. To use an environment variable instead, set `bearer_token_env`; when both exist, the stored credential takes precedence.

During the versioned account migration only, an old `provider:<id>` credential is copied to `account:<id>` and read back before committing configuration. A different existing target credential is a conflict, not permission to overwrite it. Original credential entries are retained, but normal execution never falls back to them. Environment-only references remain environment-only; no blank key is manufactured. Do not delete old credentials or edit migration records as a repair.

Account IDs are stable after creation. Changing the display name does not rekey credentials, routes, catalogs or statistics. Create an account from an account template; its default name follows the template display name, and multiple accounts may use the same template. The model identity in selectors and top-level statistics is `(account_id, configured model_id)`; reasoning effort is a second-level breakdown and sent/reported models remain diagnostics. Unknown historical identities stay unknown.

The four built-in Zhipu MCP servers only borrow a usable key from `template = "zhipu-coding-plan"`. With multiple instances, the first usable key in stable account-ID order wins. Ordinary `zhipu` templates and matching endpoint hosts are not credential fallbacks. A missing/blank key does not connect, discover or register callable tools; an explicit builtin disable remains disabled. They use the same generic MCP runtime and published-generation leases as user MCP servers, with no account-specific Thread.

## Model catalog sources

A account catalog either bundles a built-in model list or declares only user models. `additional_models` entries are user-authored and the only entries a user may add or delete; a `Bundled` catalog without an observation still resolves to its built-in list.

Online discovery is declared per catalog, never per adapter: a catalog that supports it records the discovery transport; no model families are excluded. During startup the runtime queries every instance whose catalog declares discovery, one independent task per instance with its own query identity, timeout and cache file. Explicit account-level model synchronization uses the same discovery and atomic publication path; repeated requests for the same query identity share the in-flight operation. A successful response replaces that instance's observed list as a whole, and a valid empty list is an accepted replacement. A failed query records that instance's typed error and retains its last successful snapshot, or its built-in list on first launch; it does not rewrite saved configuration or reset selections. Catalog status and account-local metadata changes publish through the separate catalog revision.

The management catalog always retains the account's bound built-in definitions alongside its current observed list and user models, deduplicated by exact (account_id, model_id). Online-only members disappear when withdrawn; missing built-in members remain `bundled`. Metadata and parameter observations resolve only inside that account, with explicit online fields ahead of that account's explicit configuration and bound built-in definitions; another account's same model_id never supplies missing values. Snapshots mark every entry's origin (`bundled`, `online`, `manual`) so the UI groups them instead of inferring from model_id differences.

Display names are the exception: an existing manual model's `display_name` takes precedence over an online name, then the account's bound built-in name, then the original model ID. A nonblank name explicitly supplied online is preserved verbatim even when it equals the model ID; only an absent, empty or whitespace-only online name falls back. Declaration presence must remain distinct from decoder-generated defaults, including cached observations. The account editor already supports names on manual models; there is no separate rename setting for built-in or online entries, and no additional setting is needed.

`model_enabled_overrides` maps exact model IDs to explicit `true` or `false`; absence means automatic. Online and manual members are enabled automatically, as are built-ins before any successful observation. Once an observation exists (including a successful empty list or last-success cache), built-ins absent from it are disabled automatically but remain visible in account settings. Users may explicitly enable them with the existing switch; this persists across restarts and source changes without changing online observations or creating manual definitions. Explicit enablement never creates an unknown member or bypasses context, modality, credential or transport admission; actual service availability is still determined by the provider. Client projections retain the backend default when no explicit override exists.

Model queries without a type return this complete catalog. Session and Agent menus request the `text` type: the backend checks text input, text output and a positive resolved context window after account-local resolution. Account settings keep the complete catalog. A saved route that no longer matches the filter remains selected with an explanation; filtering never rewrites routes or replaces request-time validation. Unknown context stays unknown unless an exact-ID declaration supplies it.

Parameter defaults are independent of candidate order. A valid explicit selection takes precedence over a configured default, then the model-declared default, then the first candidate. Online defaults retain their own declaration order: missing fields and HTTP 304 do not promote an old value, explicit null clears it, and a default cannot restore withdrawn candidates. Cache normalization upgrades keep the last successful snapshot while forcing a fresh response body before resuming conditional requests.

The model section offers explicit synchronization, not periodic polling. It preserves existing models and all user overrides on failure, and account configuration, credential changes or deletion prevent stale results from publishing. Deleting a user model requires an expected settings revision, is rejected for non-user entries, and also removes that model_id's enablement, connection and compaction overrides. Supported online prices with explicit currency and token units override only that account route; missing or unsupported prices keep the local route price. Invalid recognized prices reject the observation. A route without a price stays unpriced rather than zero, and a catalog change never recomputes recorded costs.

The Accounts tab reads canonical account and model-domain snapshots through their repositories; it does not poll instances or implicitly synchronize when the tab becomes visible. The read-only `usageQueryRevision` is a non-secret, runtime-owned query identity, not a TOML setting or secret fingerprint.

## Minimal Working Example

Every account needs `name`, `base_url`, and a `catalog` section. The two root Mode routes are required;
a system child route is optional and, when present, is an explicit override. `effort` is optional and
must match the model's supported effort candidates.

```toml
schema_version = 27

[deepseek_web_search]
enabled = true
fetch_enabled = true

[models.accounts.deepseek]
template = "deepseek"
protocol = "deep_seek"
name = "DeepSeek"
base_url = "https://api.deepseek.com"
bearer_token_env = "DEEPSEEK_API_KEY"

[models.accounts.deepseek.catalog]
source = "bundled"
catalog = "deepseek"

[models.routes.explorer]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.simple"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

[mode_model_routes."mode.task"]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"

```

## Safe Editing Workflow

1. Prefer the Settings page; it validates and persists correctly.
2. For manual edits, copy `config.toml` aside first.
3. Keep `schema_version` and both built-in Mode routes valid. Any explicit system-child route must reference a currently declared child ID and remain valid; omitted entries inherit without being persisted.
4. Reference tokens via `bearer_token_env`; never paste raw tokens.
5. Add accounts from Settings or a template (`deepseek`, `openai`, `zhipu`, ...) rather than hand-writing catalog metadata.
6. After external edits, use explicit reload and confirm the canonical settings reflect the change. If validation fails, preserve the original settings and report the error; do not restart as a repair step.
7. Work-mode JSON validation and schema are exposed by the Settings editor and the runtime APIs `validate_thread_mode_definition` and `thread_mode_definition_schema`, not a standalone shell command. External edits require explicit reload; built-in IDs are never valid save targets.
