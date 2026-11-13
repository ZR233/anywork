# Other configuration and storage

## SSH connections

Connections use the standard user's OpenSSH file: `$HOME/.ssh/config` on Unix,
`%USERPROFILE%\.ssh\config` on Windows, independently of Studio home. It is SSH
configuration syntax, not TOML:

```sshconfig
Host development
    HostName dev.example.com
    User developer
    Port 22
    IdentityFile ~/.ssh/id_ed25519
```

Use a literal single alias for a selectable Studio entry. `HostName` defaults to
the alias; port defaults to 22. Wildcard/multiple-pattern Host entries and Include
are not selectable entries in Studio's parser. Do not assume it implements every
OpenSSH configuration feature. The connection itself still uses SSH.

Studio edits only its managed blocks between `# BEGIN anywork server: <alias>` and
the matching END marker. Handwritten entries are read-only in the product editor;
other bytes are preserved. Use the connection UI to reload/select and verify an
actual connection. Keep passwords in the product credential flow and private keys
in their intended files; neither belongs in MCP TOML.

## Skill files and project instructions

User skills are read from the platform user's `.agents/skills/<name>/SKILL.md`.
Project skills default to `<workspace>/.agents/skills/<name>/SKILL.md`; the main
config can change `skills.project_dir` and add `skills.external_dirs`.
Each skill uses Markdown with YAML frontmatter, for example:

```markdown
---
name: example-workflow
description: Explain the concrete task this skill supports and when to use it.
---

# Example workflow

Instructions for the task. Link detailed material under references/ when needed.
```

Use `references/`, `scripts/`, `assets/` and `templates/` only when needed and keep
references within the skill. User skills are read-only; place authorized project
skill edits in the project directory. Inspect the current discovered skill catalog
after reload; a directory's existence alone does not prove discovery or enablement.

Project instructions are read from workspace root through the current directory.
Each directory selects the first existing candidate: `AGENTS.override.md`,
`AGENTS.md`, `Agents.md`, then `instructions.project_doc_fallback_filenames`.
The configured byte limit applies to the combined content. These Markdown
documents provide task context, not new tool permissions. Do not write model
credentials or runtime database paths into reusable instructions.

## Runtime-owned files

`<studio-home>/data/` contains the product database, catalogs, workspace/session
indexes, model observations and call records. Workspace/session keys hash stable
IDs, not display names. `workspace.toml`, `session.toml`, checkpoints, history
databases, attachments and resource indexes are runtime-owned, not manual settings.

Bots are managed through the Bots UI. Their schema-4 configuration is stored at
`<studio-home>/data/bots/<bot-id>/config.toml` with `state.sqlite`; workspace
identity, revision, timestamps and credential references are coordinated by the
runtime. Do not hand-author or overwrite these files. App Secrets use protected
`bot:<bot-id>` credentials, not TOML or SQLite. Verify connection status and an
authorized bot operation separately from a successful settings save.

Use the latest `studio.session-files` host fact for the current Thread's execution
`scratch`, `artifacts` and command-output paths. SSH paths belong to its remote
workspace, and each child has its own directory. Do not derive these paths from
another Thread or a previous run. Temporary auxiliary files belong in scratch;
deliverables belong in artifacts or the user's requested location. Tool-owned
output directories retain their defined locations.

Host transfer staging, attachment drafts, helper caches, credential transaction
journals, migration backups and startup recovery records are not general-purpose
scratch or editable settings. Preserve originals and diagnostics on failure;
never reset data or remove journals to make an unrelated configuration task pass.

SSH connections are explicit and shared by active workspaces on the same server.
Disconnect or transport failure permanently closes existing process/file/LSP
handles. Connect creates a fresh execution binding; it does not resume commands,
file uploads, directory cursors or language servers. Do not retry a mutation from
a lost response without checking its actual result. OpenSSH user settings still
apply; anywork does not add keepalive settings or an automatic reconnect policy.
Project Skills and LSP files are read on their workspace target; user, system and
external read-only Skills remain on the desktop. Check each resource's actual
source before editing. No configuration format or field changes are required.
