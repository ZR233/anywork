use super::super::read_budget::{FieldTable, bounded_header, count, require_budget, text_chunk};
use super::source::RecoverySnapshot;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::{
    primitives::{TextReadItem, TextReadPage, TypedListRef},
    recovery::*,
};
use pl_protocol::studio::{ReadText, StudioError, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Id(usize),
    Project(usize),
    Thread(usize),
    Message(usize),
    Owner(usize),
    State(usize),
    Root(usize),
    Path(usize),
    Branch(usize),
    Base(usize),
    Head(usize),
    Changed(usize, usize),
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum List {
    Issues,
    Changed(usize),
}
pub(super) struct RecoveryMaterial {
    pub source: Arc<RecoverySnapshot>,
    texts: FieldTable<Text>,
    lists: FieldTable<List>,
}
impl RecoveryMaterial {
    pub fn new(source: Arc<RecoverySnapshot>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    fn values(&self) -> Result<&[crate::StudioRecoveryIssue], StudioError> {
        self.source
            .value
            .as_deref()
            .map(Vec::as_slice)
            .ok_or_else(wrong)
    }
    pub fn header(&self) -> Result<RecoveryReadHeader, StudioError> {
        Ok(RecoveryReadHeader {
            issues: TypedListRef {
                list_id: self.lists.register(List::Issues)?,
                total: count(self.values()?.len())?,
            },
        })
    }
    pub fn entries(&self, offset: u64, limit: u32) -> Result<RecoveryEntryPage, StudioError> {
        let (start, end, next_offset) = range(self.source.entities.len(), offset, limit)?;
        Ok(RecoveryEntryPage {
            collection: self.source.collection.ok_or_else(wrong)?,
            offset,
            items: self.source.entities[start..end].to_vec(),
            next_offset,
        })
    }
    pub fn entity(&self, reference: ProductEntityRef) -> Result<RecoveryEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|entry| entry == &reference)
            .ok_or_else(wrong)?;
        bounded_header(|inline| {
            Ok(RecoveryEntityRead {
                reference,
                value: self.issue(index, inline)?,
            })
        })
    }
    pub fn lookup(&self, id: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .values()?
            .iter()
            .position(|issue| issue.id == id)
            .map(|index| self.source.entities[index]))
    }
    pub fn issues(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<RecoveryIssueReadPage, StudioError> {
        if self.lists.field(list_id)? != List::Issues {
            return Err(wrong());
        }
        let values = self.values()?;
        let (start, end, _) = range(values.len(), offset, limit)?;
        let mut page = RecoveryIssueReadPage {
            list_id,
            offset,
            total: count(values.len())?,
            items: Vec::new(),
            next_offset: None,
        };
        for index in start..end {
            page.items.push(self.issue(index, 0)?);
            page.next_offset = next(index + 1, values.len())?;
            if let Err(error) = require_budget(&page) {
                page.items.pop();
                if page.items.is_empty() {
                    return Err(error);
                }
                page.next_offset = Some(count(index)?);
                break;
            }
        }
        Ok(page)
    }
    pub fn changed_files(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<TextReadPage, StudioError> {
        let List::Changed(issue) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let values = &self
            .values()?
            .get(issue)
            .and_then(|issue| issue.worktree.as_ref())
            .ok_or_else(wrong)?
            .changed_files;
        let (start, end, _) = range(values.len(), offset, limit)?;
        let mut page = TextReadPage {
            list_id,
            offset,
            total: count(values.len())?,
            items: Vec::new(),
            next_offset: None,
        };
        for index in start..end {
            page.items.push(TextReadItem {
                value: self.read(Text::Changed(issue, index), 0)?,
            });
            page.next_offset = next(index + 1, values.len())?;
            if let Err(error) = require_budget(&page) {
                page.items.pop();
                if page.items.is_empty() {
                    return Err(error);
                }
                page.next_offset = Some(count(index)?);
                break;
            }
        }
        Ok(page)
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.text_source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }
    fn read(&self, field: Text, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    fn issue(&self, index: usize, inline: usize) -> Result<RecoveryIssueRead, StudioError> {
        let value = self.values()?.get(index).ok_or_else(wrong)?;
        let worktree = value
            .worktree
            .as_ref()
            .map(|tree| -> Result<_, StudioError> {
                Ok(WorktreeRecoveryPreviewRead {
                    owner_kind: match tree.owner_kind {
                        crate::StudioRecoveryWorktreeOwner::Session => WorktreeOwner::Session,
                        crate::StudioRecoveryWorktreeOwner::Child => WorktreeOwner::Child,
                    },
                    owner_thread_id: self.read(Text::Owner(index), inline)?,
                    lease_revision: tree.lease_revision,
                    state: self.read(Text::State(index), inline)?,
                    repository_root: self.read(Text::Root(index), inline)?,
                    path: self.read(Text::Path(index), inline)?,
                    branch: self.read(Text::Branch(index), inline)?,
                    base_commit: self.read(Text::Base(index), inline)?,
                    head_commit: tree
                        .head_commit
                        .as_ref()
                        .map(|_| self.read(Text::Head(index), inline))
                        .transpose()?,
                    dirty: tree.dirty,
                    changed_files: TypedListRef {
                        list_id: self.lists.register(List::Changed(index))?,
                        total: count(tree.changed_files.len())?,
                    },
                })
            })
            .transpose()?;
        Ok(RecoveryIssueRead {
            id: self.read(Text::Id(index), inline)?,
            scope: match value.scope {
                crate::StudioRecoveryIssueScope::Application => RecoveryScope::Application,
                crate::StudioRecoveryIssueScope::Project => RecoveryScope::Project,
                crate::StudioRecoveryIssueScope::Thread => RecoveryScope::Thread,
            },
            category: match value.category {
                crate::StudioRecoveryIssueCategory::ProcessLease => RecoveryCategory::ProcessLease,
                crate::StudioRecoveryIssueCategory::ToolCatalog => RecoveryCategory::ToolCatalog,
                crate::StudioRecoveryIssueCategory::Repository => RecoveryCategory::Repository,
                crate::StudioRecoveryIssueCategory::Storage => RecoveryCategory::Storage,
            },
            action: match value.action {
                crate::StudioRecoveryIssueAction::None => RecoveryAction::None,
                crate::StudioRecoveryIssueAction::Retry => RecoveryAction::Retry,
                crate::StudioRecoveryIssueAction::CleanupThread => RecoveryAction::CleanupThread,
                crate::StudioRecoveryIssueAction::RemoveProject => RecoveryAction::RemoveProject,
                crate::StudioRecoveryIssueAction::CleanupWorktree => {
                    RecoveryAction::CleanupWorktree
                }
            },
            project_id: value
                .project_id
                .as_ref()
                .map(|_| self.read(Text::Project(index), inline))
                .transpose()?,
            thread_id: value
                .thread_id
                .as_ref()
                .map(|_| self.read(Text::Thread(index), inline))
                .transpose()?,
            message: self.read(Text::Message(index), inline)?,
            worktree,
        })
    }
    fn text_source(&self, field: Text) -> Result<&str, StudioError> {
        let index = match field {
            Text::Id(i)
            | Text::Project(i)
            | Text::Thread(i)
            | Text::Message(i)
            | Text::Owner(i)
            | Text::State(i)
            | Text::Root(i)
            | Text::Path(i)
            | Text::Branch(i)
            | Text::Base(i)
            | Text::Head(i)
            | Text::Changed(i, _) => i,
        };
        let value = self.values()?.get(index).ok_or_else(wrong)?;
        match field {
            Text::Id(_) => Ok(&value.id),
            Text::Project(_) => value.project_id.as_deref().ok_or_else(wrong),
            Text::Thread(_) => value.thread_id.as_deref().ok_or_else(wrong),
            Text::Message(_) => Ok(&value.message),
            _ => {
                let tree = value.worktree.as_ref().ok_or_else(wrong)?;
                match field {
                    Text::Owner(_) => Ok(&tree.owner_thread_id),
                    Text::State(_) => Ok(&tree.state),
                    Text::Root(_) => Ok(&tree.repository_root),
                    Text::Path(_) => Ok(&tree.path),
                    Text::Branch(_) => Ok(&tree.branch),
                    Text::Base(_) => Ok(&tree.base_commit),
                    Text::Head(_) => tree.head_commit.as_deref().ok_or_else(wrong),
                    Text::Changed(_, index) => tree
                        .changed_files
                        .get(index)
                        .map(String::as_str)
                        .ok_or_else(wrong),
                    _ => Err(wrong()),
                }
            }
        }
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown Recovery field, list or member in the original scope")
}
fn range(
    total: usize,
    offset: u64,
    limit: u32,
) -> Result<(usize, usize, Option<u64>), StudioError> {
    if !(1..=100).contains(&limit) {
        return Err(StudioError::invalid_argument(
            "Page limit must be in 1..=100",
        ));
    }
    let start = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= total)
        .ok_or_else(wrong)?;
    let end = start.saturating_add(limit as usize).min(total);
    Ok((start, end, next(end, total)?))
}
fn next(end: usize, total: usize) -> Result<Option<u64>, StudioError> {
    if end < total {
        Ok(Some(count(end)?))
    } else {
        Ok(None)
    }
}
