//! Session note access through opaque Thread extensions instead of core business state.
use super::*;
use pl_agent_tool::typed::decode_json;
use pl_core::context::{ContextContent, OpaquePayload};
use pl_core::thread::extensions::ExtensionMutation;
use pl_core::tool::{
    ToolOutput,
    opaque::{CallContext, Registration, ToolError},
};
use std::sync::Arc;

const NOTE_FORMAT: &str = "pl.tool.session-note";

/// A note operation with no mutable state outside its owning Thread.
#[derive(Debug)]
pub struct NoteTool {
    definition: pl_agent_tool::ToolDefinition,
    kind: SessionNoteToolKind,
}

/// Registers one operation with explicit state-update authority only for writes and patches.
///
/// The supplied definition is frozen once by the host before constructing the instance.
pub fn registration(
    kind: SessionNoteToolKind,
    prepared: pl_core::tool::opaque::PreparedRegistration,
    definition: pl_agent_tool::ToolDefinition,
) -> Registration {
    let contract = match kind {
        SessionNoteToolKind::Read => "builtin.read_session_note@1",
        SessionNoteToolKind::Search => "builtin.search_session_note@1",
        SessionNoteToolKind::Write => "builtin.write_session_note@1",
        SessionNoteToolKind::ApplyPatch => "builtin.apply_session_note_patch@1",
    };
    let registration = prepared
        .attach(pl_agent_tool::ToolHandle::new(NoteTool::new(
            kind, definition,
        )))
        .with_presentation_contract(pl_core::model::ToolPresentationContract::new(contract));
    match kind {
        SessionNoteToolKind::Read | SessionNoteToolKind::Search => registration,
        SessionNoteToolKind::Write | SessionNoteToolKind::ApplyPatch => {
            registration.with_extension_updates()
        }
    }
}

impl pl_agent_tool::Tool for NoteTool {
    type Input = pl_core::context::OpaquePayload;
    type Context = pl_core::tool::opaque::CallContext;
    type Output = pl_core::tool::ToolOutput;
    type Error = pl_core::tool::opaque::ToolError;

    fn definition(&self) -> &pl_agent_tool::ToolDefinition {
        &self.definition
    }

    async fn execute(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> std::result::Result<ToolOutput, ToolError> {
        self.execute_note(input, context).await
    }
}

impl NoteTool {
    /// Constructs an operation over the invocation's immutable extension snapshot.
    pub fn new(kind: SessionNoteToolKind, definition: pl_agent_tool::ToolDefinition) -> Self {
        Self { definition, kind }
    }
    async fn execute_note(
        &self,
        input: OpaquePayload,
        context: CallContext,
    ) -> std::result::Result<ToolOutput, ToolError> {
        let arguments = input.content();
        let previous = context.extensions.get(NOTE_FORMAT);
        if previous.is_some_and(|record| {
            record.payload.format() != NOTE_FORMAT || record.payload.version() != 1
        }) {
            return Err(ToolError::new(tool_error(
                self.kind.name(),
                "unsupported saved note format or version",
            )));
        }
        let mut note = pl_protocol::SessionNote {
            revision: previous.map_or(0, |record| record.revision),
            content: previous
                .map_or_else(String::new, |record| record.payload.content().to_owned()),
            content_hash: String::new(),
            updated_at: 0,
        };
        note.content_hash = pl_core::context::content_hash(note.content.as_bytes());
        let mut mutations = Vec::new();
        let result = match self.kind {
            SessionNoteToolKind::Read => {
                read_note(decode_json(arguments).map_err(ToolError::new)?, &note)
                    .map_err(ToolError::new)?
            }
            SessionNoteToolKind::Search => {
                search_note(decode_json(arguments).map_err(ToolError::new)?, &note)
                    .map_err(ToolError::new)?
            }
            SessionNoteToolKind::Write | SessionNoteToolKind::ApplyPatch => {
                let (expected, content, status) = match self.kind {
                    SessionNoteToolKind::Write => {
                        let input: WriteInput = decode_json(arguments).map_err(ToolError::new)?;
                        (input.expected_revision(), input.content, "written")
                    }
                    SessionNoteToolKind::ApplyPatch => {
                        let input: ApplyPatchInput =
                            decode_json(arguments).map_err(ToolError::new)?;
                        let content = patch::apply(
                            (!note.content.is_empty()).then(|| note.content.clone()),
                            &input.patch,
                        )
                        .await
                        .map_err(ToolError::new)?;
                        (input.expected_revision(), content, "patched")
                    }
                    SessionNoteToolKind::Read | SessionNoteToolKind::Search => {
                        unreachable!("write operation selected above")
                    }
                };
                validate_expected_revision(self.kind.name(), Some(expected), note.revision)
                    .map_err(ToolError::new)?;
                if content.len() > MAX_SESSION_NOTE_BYTES {
                    return Err(ToolError::new(tool_error(
                        self.kind.name(),
                        "session note exceeds 1048576 bytes",
                    )));
                }
                if content != note.content {
                    note.revision = context.extension_sequence.checked_add(1).ok_or_else(|| {
                        ToolError::new(tool_error(self.kind.name(), "note revision exhausted"))
                    })?;
                    note.content = content;
                    note.content_hash = pl_core::context::content_hash(note.content.as_bytes());
                    mutations.push(ExtensionMutation::Put {
                        id: NOTE_FORMAT.into(),
                        expected_revision: previous.map(|record| record.revision),
                        payload: OpaquePayload::new(NOTE_FORMAT, 1, note.content.clone())
                            .map_err(|error| ToolError::new(tool_error(self.kind.name(), error)))?,
                    });
                }
                note_result(status, &note)
            }
        };
        let result = serde_json::to_string(&result)
            .map_err(pl_protocol::PureError::from)
            .map_err(ToolError::new)?;
        Ok(ToolOutput::new(
            OpaquePayload::text(result.clone()),
            vec![ContextContent::Text {
                text: Arc::from(result),
            }],
        )
        .with_extension_mutations(mutations))
    }
}
