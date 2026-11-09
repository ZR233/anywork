//! Host mapping for the independent command validators.
use pl_core::tool::opaque::ToolError;

#[derive(Debug, thiserror::Error)]
#[error("{0}")]
pub struct ExecInputError(#[source] pub pl_tool_process::input::ExecInputError);
impl std::ops::Deref for ExecInputError {
    type Target = pl_tool_process::input::ExecInputError;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
impl ExecInputError {
    pub fn into_tool_error(self) -> ToolError {
        match self
            .0
            .diagnostic_json()
            .map_err(ToolError::new)
            .and_then(|text| super::output::receipt_output("pl.tool.exec", text))
        {
            Ok(output) => ToolError::new(self).with_output(output),
            Err(error) => error,
        }
    }
}
pub fn parse_and_validate_exec_input(
    raw: &str,
) -> Result<super::ValidatedExecInput, ExecInputError> {
    pl_tool_exec::parse_and_validate_exec_input(raw).map_err(ExecInputError)
}
pub fn parse_and_validate_stdin_input(raw: &str) -> Result<super::WriteStdinInput, ExecInputError> {
    pl_tool_write_stdin::parse_and_validate_stdin_input(raw).map_err(ExecInputError)
}
