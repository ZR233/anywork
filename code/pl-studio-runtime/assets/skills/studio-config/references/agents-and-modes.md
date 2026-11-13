# Agent Profiles and work modes

Profiles select child Agent behavior and backend. Work modes define the root
Thread's workflow. They are separate file types, not interchangeable role settings.

## User Agent Profiles

Store each UTF-8 TOML file at `<studio-home>/agents/<profile-id>.toml`.
The filename supplies the ID; use 1–64 lowercase ASCII letters, digits, `-` or `_`.
Built-in child IDs and root IDs are reserved. Current schema is `3`.

```toml
schema_version = 3
enabled = true
display_name = "Code reviewer"
description = "Review a bounded code change."
when_to_use = "Use for independent code review."
workspace_mode = "directory"

[binding]
kind = "native"
system_instructions = "Review the requested change and report actionable findings."

[binding.route]
account_id = "deepseek"
model_id = "deepseek-flash"
effort = "high"
```

`display_name`, `description`, `when_to_use` and `binding` are required; text fields
must be nonblank. `enabled` defaults to `true`. `workspace_mode` defaults to
`directory`; alternatives are `unrestricted`, `worktree`, `review`. The mode controls
workspace selection, not permission escalation.

A Native child requires nonblank `binding.system_instructions` and a route with
`account_id`, `model_id`, optional supported `effort`. Substitute an existing usable
account/model; do not create a fake account merely to satisfy a Profile.

An ACP binding instead contains exactly the backend reference:

```toml
[binding]
kind = "acp"
account_id = "antigravity"
```

This replaces the whole Native binding, including its route. It references an
existing user-level ACP definition; do not persist a runtime connection revision
in the Profile. It has no Native model or instruction placeholders. ACP Profiles
can dispatch ordinary children when their referenced definition is valid and enabled,
in both delegation modes. Automatic model selection applies only to Native children;
do not supply `modelSelection`, Native effort, `writablePaths`, structured review or
Native workflow arguments to an ACP child. New ACP children use the service's default
session configuration; later configuration changes belong to that session.

ACP callers receive the `anywork_` collaboration tools through direct HTTP when advertised,
or the standard ACP v1 stdio MCP transport otherwise. The host provides the authenticated
instance-local service. HTTP and stdio share one MCP handler; the native `pl-studio-mcp`
stdio server calls the original runtime over local IPC, without an HTTP MCP relay.
Do not persist transient IPC endpoints or capabilities, add them to prompts, or change
the agent's own MCP settings. Packaged applications must contain the host-native
`pl-studio-mcp` in `data/host-mcp/<target>/` separately from Linux SSH workers.
Bundled sources never fall back to PATH; unpackaged entries use an explicit external
source. HTTP capability alone is not the
qualification for an ACP child. Tool prefixes and prompt instructions do not
disable the service's own tools. If the service advertises `systemPrompt`, host
instructions use its `append` mode; otherwise they accompany user prompt content.

For an unpackaged host using the external source, install the executable from the
same source revision with `cargo install --path code/pl-studio-mcp --locked` and
ensure it is on that host process's PATH. The SSH supervisor remains a separate
`pl-remote-helper` installation. Desktop `build-gui`, `run-gui`, and native tests
prepare both assets through xtask. `ANYWORK_HOST_MCP_DIR` is an xtask build input,
not an ACP account setting; `ANYWORK_HOST_IPC_ENDPOINT` and
`ANYWORK_HOST_IPC_CAPABILITY` are per-instance runtime values. Never copy these
values into user configuration.

Use the Agents settings save/reload operation after editing and inspect its
diagnostics and executable catalog. File validity and route availability differ;
an unavailable route must not silently select another model. Already running
children retain their frozen configuration. Built-in declarations are not editable
Profile files; their enablement and optional routes belong to the main config.

## Work modes

Custom modes live at `<studio-home>/modes/<mode-id>.json`. The filename must equal
the document `id` plus `.json`. Use the current JSON editing shape below, without
a TOML schema header. `mode.simple` and `mode.task` are built-in and read-only.

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

The six execution fields are `id`, `displayName`, `description`, `order`, `prompt`,
`workflow`; `editor` is optional layout data. Use the Settings editor's schema and
validation for other workflow node kinds rather than inventing fields.

The compiler validates unique state IDs and transition identities, existing initial
state/endpoints, completion criteria for atomic stages, no outgoing transitions from
final stages, and reachability to a final stage. Editor nodes use existing state IDs
and finite coordinates; layout does not change workflow execution.

Saving validates before publication. External JSON edits require explicit mode
reload. A malformed document, filename mismatch, unknown field or compiler error
rejects the reload and retains the previous published catalog. The product exposes
`thread_mode_definition_schema` and `validate_thread_mode_definition` APIs; these
are not standalone shell commands. Custom modes use `mode.simple`'s model route
unless the main config supplies their own `mode_model_routes` entry.
