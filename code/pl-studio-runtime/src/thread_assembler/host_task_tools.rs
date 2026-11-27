//! Shared task catalog; each consumer supplies its real task owner, never fake Native records.
use super::ThreadAssemblyError;
use pl_agent_tool::ToolDefinition;
use pl_core::tool::opaque::Registration;
use pl_tool::{
    binding::{PreparedNativeTool, ToolCallPolicy, prepare_native_tool, prepare_registration},
    task_control::{ListTasksTool, TaskControlKind, TaskControlTool},
};

pub(crate) trait HostTaskSink {
    type Error: From<pl_agent_tool::DefinitionError>;
    fn list(&mut self, prepared: PreparedNativeTool<ListTasksTool>) -> Result<(), Self::Error>;
    fn control(
        &mut self,
        definition: ToolDefinition,
        kind: TaskControlKind,
    ) -> Result<(), Self::Error>;
}

pub(crate) fn list<S: HostTaskSink>(sink: &mut S) -> Result<(), S::Error> {
    sink.list(prepare_native_tool::<ListTasksTool>()?.with_output_schema(
        pl_agent_tool::typed::output_schema_for::<Vec<pl_tool::task_control::TaskStatusView>>(),
    )?)
}

pub(crate) fn controls<S: HostTaskSink>(sink: &mut S) -> Result<(), S::Error> {
    for kind in [
        TaskControlKind::Wait,
        TaskControlKind::Query,
        TaskControlKind::Cancel,
    ] {
        let definition = pl_tool::thread_catalog::ThreadBuiltin::Task(kind).declaration();
        sink.control(definition, kind)?;
    }
    Ok(())
}

pub(crate) struct NativeTaskTools<'a>(pub &'a mut Vec<Registration>);
impl HostTaskSink for NativeTaskTools<'_> {
    type Error = ThreadAssemblyError;
    fn list(&mut self, adapter: PreparedNativeTool<ListTasksTool>) -> Result<(), Self::Error> {
        let prepared = prepare_registration(
            adapter.definition().name(),
            adapter.definition(),
            ToolCallPolicy::DirectOnly,
        )?;
        self.0.push(prepared.attach(pl_agent_tool::ToolHandle::new(
            adapter.attach(ListTasksTool),
        )));
        Ok(())
    }
    fn control(
        &mut self,
        definition: ToolDefinition,
        kind: TaskControlKind,
    ) -> Result<(), Self::Error> {
        let prepared =
            prepare_registration(definition.name(), &definition, ToolCallPolicy::DirectOnly)?;
        self.0
            .push(TaskControlTool::new(kind, definition).registration(prepared));
        Ok(())
    }
}
