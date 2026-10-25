use std::sync::Arc;

use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::execution::{
    ActivityReadHeader, ActivityToolPage, ActivityToolReadItem, IndexedActivityToolReadItem,
    WaitReadIntent, WaitReadValue, WaitTargetPage, WaitTargetReadItem,
};
use pl_protocol::{ThreadActivity, ThreadActivityToolEntry, ThreadWaitIntent, ThreadWaitTarget};

use super::super::read_budget::{FieldTable, bounded_header, count, protocol, text_chunk};
use super::budget::{page, validate_revision};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Tool {
    Active(usize),
    Latest,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum ToolField {
    CallId,
    TaskId,
    Name,
    Summary,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum TargetField {
    TaskId,
    ToolName,
    Summary,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    ThreadId,
    Identity,
    TurnId,
    InputId,
    AttemptId,
    Summary,
    Tool(Tool, ToolField),
    Target(Tool, usize, TargetField),
}

pub(in crate::studio::runtime) struct ActivityMaterial {
    scope: ReadScopeIdentity,
    source: Arc<ThreadActivity>,
    fields: FieldTable<Field>,
}

impl ActivityMaterial {
    pub(in crate::studio::runtime) fn new(
        scope: ReadScopeIdentity,
        source: Arc<ThreadActivity>,
    ) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        Ok(Self {
            scope,
            source,
            fields: FieldTable::default(),
        })
    }

    pub(in crate::studio::runtime) fn header(&self) -> Result<ActivityReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(ActivityReadHeader {
                scope: self.scope.clone(),
                thread_id: self.read(Field::ThreadId, inline)?,
                identity: self.read(Field::Identity, inline)?,
                turn_id: self.read(Field::TurnId, inline)?,
                revision: self.source.revision,
                input_id: self
                    .source
                    .input_id
                    .as_ref()
                    .map(|_| self.read(Field::InputId, inline))
                    .transpose()?,
                attempt_id: self
                    .source
                    .attempt_id
                    .as_ref()
                    .map(|_| self.read(Field::AttemptId, inline))
                    .transpose()?,
                kind: self.source.kind,
                summary: self.read(Field::Summary, inline)?,
                summary_truncated: self.source.summary_truncated,
                count: self.source.tools.count,
                background: self.source.tools.background,
                active_count: count(self.source.tools.active.len())?,
                latest_started: self
                    .source
                    .tools
                    .latest_started
                    .as_ref()
                    .map(|_| self.tool(Tool::Latest, inline))
                    .transpose()?,
            })
        })
    }

    pub(in crate::studio::runtime) fn tools(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<ActivityToolPage, StudioError> {
        let result = page(
            &self.scope,
            self.source.tools.active.len(),
            offset,
            limit,
            |index, inline| {
                let value = self.tool(Tool::Active(index), inline)?;
                Ok(IndexedActivityToolReadItem {
                    index: count(index)?,
                    call_id: value.call_id,
                    task_id: value.task_id,
                    name: value.name,
                    summary: value.summary,
                    arguments: value.arguments,
                    state: value.state,
                    ordinal: value.ordinal,
                    started_at: value.started_at,
                    wait: value.wait,
                })
            },
        )?;
        Ok(ActivityToolPage {
            scope: result.scope,
            offset: result.offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    pub(in crate::studio::runtime) fn wait_targets(
        &self,
        tool_index: u64,
        offset: u64,
        limit: u32,
    ) -> Result<WaitTargetPage, StudioError> {
        let index = usize::try_from(tool_index).map_err(|_| {
            StudioError::invalid_argument("Tool index exceeds the pinned activity list")
        })?;
        self.targets_page(Tool::Active(index), offset, limit)
    }

    pub(in crate::studio::runtime) fn latest_wait_targets(
        &self,
        offset: u64,
        limit: u32,
    ) -> Result<WaitTargetPage, StudioError> {
        self.targets_page(Tool::Latest, offset, limit)
    }

    pub(in crate::studio::runtime) fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.source_text(self.fields.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }

    fn tool(&self, key: Tool, inline: usize) -> Result<ActivityToolReadItem, StudioError> {
        let value = self.source_tool(key)?;
        let wait = value
            .wait
            .as_ref()
            .map(|wait| {
                Ok::<_, StudioError>(WaitReadValue {
                    intent: match wait.intent() {
                        ThreadWaitIntent::Events {
                            targets,
                            timeout_ms,
                        } => WaitReadIntent::Events {
                            target_count: count(targets.len())?,
                            timeout_ms: *timeout_ms,
                        },
                        ThreadWaitIntent::Timer { duration_ms } => WaitReadIntent::Timer {
                            duration_ms: *duration_ms,
                        },
                    },
                    state: wait.state(),
                    messages_ready: wait.messages_ready(),
                })
            })
            .transpose()?;
        Ok(ActivityToolReadItem {
            call_id: self.read(Field::Tool(key, ToolField::CallId), inline)?,
            task_id: value
                .task_id
                .as_ref()
                .map(|_| self.read(Field::Tool(key, ToolField::TaskId), inline))
                .transpose()?,
            name: self.read(Field::Tool(key, ToolField::Name), inline)?,
            summary: self.read(Field::Tool(key, ToolField::Summary), inline)?,
            arguments: value.arguments,
            state: value.state,
            ordinal: value.ordinal,
            started_at: value.started_at,
            wait,
        })
    }

    fn targets_page(
        &self,
        key: Tool,
        offset: u64,
        limit: u32,
    ) -> Result<WaitTargetPage, StudioError> {
        let targets = self.targets(key)?;
        let result = page(
            &self.scope,
            targets.len(),
            offset,
            limit,
            |index, inline| {
                let value = &targets[index];
                Ok(WaitTargetReadItem {
                    index: count(index)?,
                    task_id: self.read(Field::Target(key, index, TargetField::TaskId), inline)?,
                    tool_name: value
                        .tool_name()
                        .map(|_| {
                            self.read(Field::Target(key, index, TargetField::ToolName), inline)
                        })
                        .transpose()?,
                    summary: value
                        .summary()
                        .map(|_| self.read(Field::Target(key, index, TargetField::Summary), inline))
                        .transpose()?,
                    summary_truncated: value.summary_truncated(),
                    status: value.status(),
                })
            },
        )?;
        Ok(WaitTargetPage {
            scope: result.scope,
            offset: result.offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }

    fn source_tool(&self, key: Tool) -> Result<&ThreadActivityToolEntry, StudioError> {
        match key {
            Tool::Active(index) => self.source.tools.active.get(index),
            Tool::Latest => self.source.tools.latest_started.as_ref(),
        }
        .ok_or_else(|| StudioError::invalid_argument("The pinned activity has no such tool entry"))
    }

    fn targets(&self, key: Tool) -> Result<&[ThreadWaitTarget], StudioError> {
        match self
            .source_tool(key)?
            .wait
            .as_ref()
            .map(pl_protocol::ThreadWaitPresentation::intent)
        {
            Some(ThreadWaitIntent::Events { targets, .. }) => Ok(targets),
            Some(ThreadWaitIntent::Timer { .. }) | None => Err(StudioError::invalid_argument(
                "Only an event wait has a target list",
            )),
        }
    }

    fn read(&self, field: Field, inline: usize) -> Result<ReadText, StudioError> {
        self.fields.read(field, self.source_text(field)?, inline)
    }

    fn source_text(&self, field: Field) -> Result<&str, StudioError> {
        let value = match field {
            Field::ThreadId => Some(self.source.thread_id.as_str()),
            Field::Identity => Some(self.source.identity.as_str()),
            Field::TurnId => Some(self.source.turn_id.as_str()),
            Field::InputId => self.source.input_id.as_deref(),
            Field::AttemptId => self.source.attempt_id.as_deref(),
            Field::Summary => Some(self.source.summary.as_str()),
            Field::Tool(tool, field) => {
                let tool = self.source_tool(tool)?;
                match field {
                    ToolField::CallId => Some(tool.call_id.as_str()),
                    ToolField::TaskId => tool.task_id.as_deref(),
                    ToolField::Name => Some(tool.name.as_str()),
                    ToolField::Summary => Some(tool.summary.as_str()),
                }
            }
            Field::Target(tool, index, field) => {
                let target = self.targets(tool)?.get(index).ok_or_else(|| {
                    protocol("Pinned wait target index no longer addresses its source")
                })?;
                match field {
                    TargetField::TaskId => Some(target.task_id()),
                    TargetField::ToolName => target.tool_name(),
                    TargetField::Summary => target.summary(),
                }
            }
        };
        value.ok_or_else(|| protocol("Text field does not address the pinned activity schema"))
    }
}
