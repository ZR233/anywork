# Bundled Agent declarations

This directory is the canonical embedded source for product Agents. Add one TOML declaration and a
Markdown instruction resource; do not add a parallel ID list or role match in configuration/UI code.
The runtime validates the complete catalog before publishing its child view.

```toml
id = "example_reader"
scope = "child"
display_name = "示例阅读者"
description = "只读检查一类项目材料。"
when_to_use = "需要独立确认指定事实时。"
instructions = "prompts/example_reader.md"
workspace_mode = "unrestricted"
```

The declaration must have a unique lowercase ASCII identity, nonempty display metadata and nonempty
instructions. `scope = "root"` requires a reserved `root:<name>` identity, one trusted `entry` value
(`studio` or `bot`) and no `workspace_mode`; exactly one declaration per required entry must validate
before startup. Rebinding an existing entry to another root declaration ID does not change the saved
binding used to restore older Threads. `scope = "child"` uses the stable child-ID character/length contract and must set a supported
`workspace_mode`. Instruction paths are normalized relative Markdown paths below `prompts/`.

Root declarations are selected only through trusted product-entry bindings; they never enter the child
Profile catalog, Settings role list or spawn schema. A new product root entry must bind its declaration
at that trusted boundary. Child declarations automatically enter the shared definition lookup, reserved
ID checks, configuration/dispatch view and Settings display. Do not expose declaration text as a free-form
root prompt or infer scope from `system`, display name, or other metadata.

System child route overrides are optional. A missing `models.routes.<id>` inherits the complete
`mode.simple` route without writing it back; an explicit invalid route stays invalid and never falls
back. Child `workspace_mode` is fixed by its declaration, not a route or user preference.

The build tracks `assets/agents`; no Rust source `include_str!` list or dependency update is needed. Keep
system-prompt cross-role collaboration rules in `src/prompts/system.md`, and put only Agent-specific
responsibility in the referenced role resource.
