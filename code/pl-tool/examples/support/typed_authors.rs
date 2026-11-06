use pl_agent_tool::ToolHandle;
use pl_core::{
    context::{ContextContent, OpaquePayload},
    tool::{
        ToolOutput,
        opaque::{CallContext, Registration, ToolError},
    },
};
use pl_tool::binding::{
    BindingError, ToolCallPolicy, prepare_json_tool, prepare_native_tool, prepare_registration,
};

#[pl_agent_tool::tool_args]
#[serde(deny_unknown_fields)]
pub struct AddArgs {
    /// First integer.
    pub left: i64,
    /// Second integer.
    pub right: i64,
}

#[derive(serde::Serialize)]
pub struct Sum {
    pub value: i64,
}

#[derive(Debug, thiserror::Error)]
#[error("integer addition overflow")]
pub struct AddError;

pub struct Add {
    offset: i64,
}

#[pl_agent_tool::tool(name = "add")]
impl Add {
    /// Adds two integers and the fixed offset.
    async fn execute(&self, args: AddArgs, _context: ()) -> Result<Sum, AddError> {
        let value = args
            .left
            .checked_add(args.right)
            .and_then(|sum| sum.checked_add(self.offset))
            .ok_or(AddError)?;
        Ok(Sum { value })
    }
}

pub fn register_add(offset: i64) -> Result<Registration, BindingError> {
    let tool = prepare_json_tool::<Add>(|_| (), ToolError::new)?;
    let registration =
        prepare_registration("example.add", tool.definition(), ToolCallPolicy::DirectOnly)?;
    Ok(registration.attach(ToolHandle::new(tool.attach(Add { offset }))))
}

#[pl_agent_tool::tool_args]
#[serde(deny_unknown_fields)]
pub struct FinishTextArgs {
    /// Complete explanation delivered when finishing the Turn.
    pub message: String,
}

#[derive(Debug, thiserror::Error)]
#[error("message must contain a non-whitespace character")]
pub struct EmptyMessage;

pub struct FinishText {
    prefix: String,
}

#[pl_agent_tool::tool(name = "finish_text")]
impl FinishText {
    /// Returns the explanation and proposes completing this Turn.
    async fn execute(
        &self,
        args: FinishTextArgs,
        context: CallContext,
    ) -> Result<ToolOutput, ToolError> {
        if args.message.trim().is_empty() {
            return Err(ToolError::new(EmptyMessage));
        }
        let text = format!("{} [{}]\n{}", self.prefix, context.turn_id, args.message);
        Ok(ToolOutput::new(
            OpaquePayload::text(text.clone()),
            vec![ContextContent::Text { text: text.into() }],
        )
        .ending_turn())
    }
}

/// The caller must explicitly grant `.with_turn_completion()` when installing this candidate.
pub fn register_finish(prefix: String) -> Result<Registration, BindingError> {
    let tool = prepare_native_tool::<FinishText>()?;
    let registration = prepare_registration(
        "example.finish",
        tool.definition(),
        ToolCallPolicy::DirectOnly,
    )?;
    Ok(registration.attach(ToolHandle::new(tool.attach(FinishText { prefix }))))
}
