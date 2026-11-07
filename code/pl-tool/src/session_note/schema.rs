use schemars::JsonSchema;
use serde::Deserialize;
use serde_json::Value;

use pl_agent_tool::typed::input_schema_for;

pub const TOOL_READ_SESSION_NOTE: &str = "read_session_note";
pub const TOOL_SEARCH_SESSION_NOTE: &str = "search_session_note";
pub const TOOL_WRITE_SESSION_NOTE: &str = "write_session_note";
pub const TOOL_APPLY_SESSION_NOTE_PATCH: &str = "apply_session_note_patch";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionNoteToolKind {
    Read,
    Search,
    Write,
    ApplyPatch,
}

impl SessionNoteToolKind {
    pub const fn all() -> &'static [Self] {
        &[Self::Read, Self::Search, Self::Write, Self::ApplyPatch]
    }

    pub const fn name(self) -> &'static str {
        match self {
            Self::Read => TOOL_READ_SESSION_NOTE,
            Self::Search => TOOL_SEARCH_SESSION_NOTE,
            Self::Write => TOOL_WRITE_SESSION_NOTE,
            Self::ApplyPatch => TOOL_APPLY_SESSION_NOTE_PATCH,
        }
    }

    pub const fn description(self) -> &'static str {
        match self {
            Self::Read => {
                "Read a targeted line range from the persistent session note. Reading every page is not required."
            }
            Self::Search => {
                "Search the persistent session note with a line-oriented literal or regular expression query before reading targeted ranges."
            }
            Self::Write => {
                "Create or replace the persistent session note when its revision still matches."
            }
            Self::ApplyPatch => {
                "Atomically edit the persistent session note with a Codex-style patch for session-note.md."
            }
        }
    }

    pub fn input_schema(self) -> Value {
        match self {
            Self::Read => input_schema_for::<ReadInput>(),
            Self::Search => input_schema_for::<SearchInput>(),
            Self::Write => input_schema_for::<WriteInput>(),
            Self::ApplyPatch => input_schema_for::<ApplyPatchInput>(),
        }
    }

    pub const fn supports_parallel_tool_calls(self) -> bool {
        matches!(self, Self::Read | Self::Search)
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct ReadInput {
    /// 1-based first line to return; defaults to 1.
    #[schemars(range(min = 1))]
    pub(super) start_line: Option<usize>,
    /// Maximum lines to return; defaults to 200.
    #[schemars(range(min = 1, max = 500))]
    pub(super) max_lines: Option<usize>,
    /// Optional revision guard.
    pub(super) expected_revision: Option<u64>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(super) struct SearchInput {
    /// Literal text or regular expression to find.
    #[schemars(length(max = 4096))]
    pub(super) query: String,
    /// Whether matching is case-sensitive; defaults to true.
    pub(super) case_sensitive: Option<bool>,
    /// Treat query as literal text instead of a regular expression.
    pub(super) literal: Option<bool>,
    /// Context lines around each match.
    #[schemars(range(max = 20))]
    pub(super) context_lines: Option<usize>,
    /// Maximum matches in this page.
    #[schemars(range(min = 1, max = 200))]
    pub(super) limit: Option<usize>,
    /// Omit on the first page; later pass the exact returned nextCursor.
    pub(super) cursor: Option<String>,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase")]
struct ExpectedRevisionInput {
    /// Revision that must still be current when the mutation is applied.
    expected_revision: u64,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct WriteWire {
    /// Complete replacement note content.
    content: String,
    /// Revision that must still be current when the mutation is applied.
    expected_revision: u64,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(from = "WriteWire")]
pub(super) struct WriteInput {
    pub(super) content: String,
    revision: ExpectedRevisionInput,
}

impl From<WriteWire> for WriteInput {
    fn from(wire: WriteWire) -> Self {
        Self {
            content: wire.content,
            revision: ExpectedRevisionInput {
                expected_revision: wire.expected_revision,
            },
        }
    }
}

impl WriteInput {
    pub(super) fn expected_revision(&self) -> u64 {
        self.revision.expected_revision
    }
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct ApplyPatchWire {
    /// Codex-style patch targeting session-note.md.
    patch: String,
    /// Revision that must still be current when the mutation is applied.
    expected_revision: u64,
}

#[derive(Debug, Deserialize, JsonSchema)]
#[serde(from = "ApplyPatchWire")]
pub(super) struct ApplyPatchInput {
    pub(super) patch: String,
    revision: ExpectedRevisionInput,
}

impl From<ApplyPatchWire> for ApplyPatchInput {
    fn from(wire: ApplyPatchWire) -> Self {
        Self {
            patch: wire.patch,
            revision: ExpectedRevisionInput {
                expected_revision: wire.expected_revision,
            },
        }
    }
}

impl ApplyPatchInput {
    pub(super) fn expected_revision(&self) -> u64 {
        self.revision.expected_revision
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_agent_tool::typed::{ArgumentError, decode_json, input_schema_for};

    #[test]
    fn revision_wire_is_strict_required_unsigned_and_lossless() {
        for (raw, patch_raw) in [
            (r#"{"content":""}"#, r#"{"patch":""}"#),
            (
                r#"{"content":"","expectedRevision":null}"#,
                r#"{"patch":"","expectedRevision":null}"#,
            ),
            (
                r#"{"content":"","expectedRevision":-1}"#,
                r#"{"patch":"","expectedRevision":-1}"#,
            ),
            (
                r#"{"content":"","expectedRevision":1,"extra":1}"#,
                r#"{"patch":"","expectedRevision":1,"extra":1}"#,
            ),
        ] {
            for error in [
                decode_json::<WriteInput>(raw).unwrap_err(),
                decode_json::<ApplyPatchInput>(patch_raw).unwrap_err(),
            ] {
                let ArgumentError::Decode { source, .. } = error else {
                    panic!("not a decode failure")
                };
                assert!(source.column() > 0);
            }
        }
        let write: WriteInput =
            decode_json(r#"{"content":"exact\ntext","expectedRevision":18446744073709551615}"#)
                .unwrap();
        let patch: ApplyPatchInput =
            decode_json(r#"{"patch":"raw patch","expectedRevision":18446744073709551615}"#)
                .unwrap();
        assert_eq!(write.expected_revision(), u64::MAX);
        assert_eq!(patch.expected_revision(), u64::MAX);
        assert_eq!(write.content, "exact\ntext");
        assert_eq!(patch.patch, "raw patch");
        for schema in [
            input_schema_for::<WriteInput>(),
            input_schema_for::<ApplyPatchInput>(),
        ] {
            assert_eq!(schema["additionalProperties"], false);
            assert!(
                schema["required"]
                    .as_array()
                    .unwrap()
                    .contains(&serde_json::json!("expectedRevision"))
            );
            assert_eq!(schema["properties"]["expectedRevision"]["type"], "integer");
            assert!(
                schema["properties"]["expectedRevision"]
                    .get("default")
                    .is_none()
            );
        }
        assert!(matches!(
            decode_json::<WriteInput>(r#"{"content":"","expectedRevision":0} true"#),
            Err(ArgumentError::Trailing { .. })
        ));
        assert!(matches!(
            decode_json::<ApplyPatchInput>(r#"{"patch":"","expectedRevision":0} true"#),
            Err(ArgumentError::Trailing { .. })
        ));
    }
}
