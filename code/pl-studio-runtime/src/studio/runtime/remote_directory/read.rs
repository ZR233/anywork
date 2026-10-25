use super::{
    super::{
        StudioRuntime,
        read_budget::{FieldTable, bounded_header, count, require_budget, text_chunk},
    },
    scope::RemoteDirectoryReadScope,
};
use anyhow::Result;
use pl_protocol::products::{identity::*, read::remote_directory::*};
use pl_protocol::remote::RemoteDirectoryListing;
use pl_protocol::studio::{FeedCloseReport, StudioError, TextChunk};
use std::{
    future::Future,
    sync::{Arc, OnceLock},
};

#[derive(Clone, Copy, PartialEq, Eq)]
enum Field {
    Path,
    Parent,
    Cursor,
    Name(usize),
    EntryPath(usize),
}
struct Page {
    listing: OnceLock<RemoteDirectoryListing>,
    texts: FieldTable<Field>,
}
pub struct StudioRemoteDirectoryRead {
    scope: RemoteDirectoryReadScope<Arc<Page>>,
}
impl StudioRuntime {
    /// Exactly one existing browse/continue call; subsequent entries offsets never perform I/O.
    pub fn open_directory(
        &self,
        alias: String,
        path: Option<String>,
        cursor: Option<String>,
    ) -> impl Future<Output = Result<StudioRemoteDirectoryRead>> + Send + 'static + use<> {
        let runtime = self.clone();
        self.read_calls.run(async move {
            runtime.remote_directory_source.ensure_open()?;
            let page = Arc::new(Page {
                listing: OnceLock::new(),
                texts: FieldTable::default(),
            });
            // Reserve the actual scope before contacting SSH, so overload cannot lose a new cursor.
            let scope = RemoteDirectoryReadScope::open(
                &runtime,
                runtime.remote_directory_source.origin(),
                ProductReadVersion::Value {
                    entry: runtime.observation_ids.next()?,
                    revision: 1,
                },
                page.clone(),
            )?;
            let listing = match runtime
                .browse_remote_directories(&alias, path, cursor.clone())
                .await
            {
                Ok(mut listing) => {
                    listing
                        .entries
                        .retain(|entry| entry.is_directory && !entry.is_symlink);
                    listing
                }
                Err(error) => {
                    let _ = scope.close().await;
                    return Err(error);
                }
            };
            runtime.remote_directory_source.remember(
                &alias,
                cursor.as_deref(),
                listing.next_cursor.as_deref(),
            );
            if let Err(error) = scope
                .ensure_open()
                .and_then(|()| runtime.remote_directory_source.ensure_open())
            {
                // Cursor remains registered if the original close fails, for shutdown/retry.
                if let Some(cursor) = &listing.next_cursor
                    && runtime
                        .close_remote_directory(&alias, cursor.clone())
                        .await
                        .is_ok()
                {
                    runtime.remote_directory_source.forget(&alias, cursor);
                }
                let _ = scope.close().await;
                return Err(error.into());
            }
            page.listing
                .set(listing)
                .map_err(|_| StudioError::internal())?;
            Ok(StudioRemoteDirectoryRead { scope })
        })
    }
    /// Delegates the original token, never reconstructs a cursor from path/offset.
    pub async fn close_directory(&self, alias: String, cursor: String) -> Result<()> {
        // Cleanup remains admitted after the read pool is sealed. Cancellation/failure retains
        // the token in the original resource owner; no cursor/path replay or replacement occurs.
        self.close_remote_directory(&alias, cursor.clone()).await?;
        self.remote_directory_source.forget(&alias, &cursor);
        Ok(())
    }
}
impl StudioRemoteDirectoryRead {
    pub fn identity(&self) -> ProductReadScopeIdentity {
        self.scope.identity()
    }
    pub fn ensure_open(&self) -> Result<(), StudioError> {
        self.scope.ensure_open()
    }
    pub fn header(
        &self,
    ) -> impl Future<Output = Result<RemoteDirectoryReadHeader>> + Send + 'static + use<> {
        let scope_id = self.scope.identity().scope_id;
        self.scope.query(move |page| {
            bounded_header(|inline| {
                let listing = page.listing()?;
                Ok(RemoteDirectoryReadHeader {
                    scope_id: scope_id.clone(),
                    path: page.read(Field::Path, inline)?,
                    parent: listing
                        .parent
                        .as_ref()
                        .map(|_| page.read(Field::Parent, inline))
                        .transpose()?,
                    next_cursor: listing
                        .next_cursor
                        .as_ref()
                        .map(|_| page.read(Field::Cursor, inline))
                        .transpose()?,
                    page_entry_count: count(listing.entries.len())?,
                })
            })
        })
    }
    pub fn entries(
        &self,
        offset: u64,
        limit: u32,
    ) -> impl Future<Output = Result<RemoteDirectoryEntryPage>> + Send + 'static + use<> {
        let scope_id = self.scope.identity().scope_id;
        self.scope.query(move |page| {
            if !(1..=100).contains(&limit) {
                return Err(StudioError::invalid_argument(
                    "Page limit must be in 1..=100",
                ));
            }
            let listing = page.listing()?;
            let total = listing.entries.len();
            let start = usize::try_from(offset)
                .ok()
                .filter(|start| *start <= total)
                .ok_or_else(wrong)?;
            let end = start.saturating_add(limit as usize).min(total);
            let mut result = RemoteDirectoryEntryPage {
                scope_id,
                offset,
                items: Vec::new(),
                next_offset: None,
            };
            for index in start..end {
                let entry = &listing.entries[index];
                result.items.push(RemoteDirectoryEntryRead {
                    name: page.read(Field::Name(index), 0)?,
                    path: page.read(Field::EntryPath(index), 0)?,
                    is_directory: entry.is_directory,
                    is_symlink: entry.is_symlink,
                });
                result.next_offset = if index + 1 < total {
                    Some(count(index + 1)?)
                } else {
                    None
                };
                if let Err(error) = require_budget(&result) {
                    result.items.pop();
                    if result.items.is_empty() {
                        return Err(error);
                    }
                    result.next_offset = Some(count(index)?);
                    break;
                }
            }
            Ok(result)
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> impl Future<Output = Result<TextChunk>> + Send + 'static + use<> {
        self.scope.query(move |page| {
            text_chunk(
                field_id,
                page.source(page.texts.field(field_id)?)?,
                offset,
                max_bytes,
            )
        })
    }
    pub fn request_close(&self) {
        self.scope.request_close();
    }
    pub async fn close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
    pub async fn retry_close(&self) -> FeedCloseReport {
        self.scope.close().await
    }
}
impl Page {
    fn listing(&self) -> Result<&RemoteDirectoryListing, StudioError> {
        self.listing.get().ok_or_else(wrong)
    }
    fn read(
        &self,
        field: Field,
        inline: usize,
    ) -> Result<pl_protocol::studio::ReadText, StudioError> {
        self.texts.read(field, self.source(field)?, inline)
    }
    fn source(&self, field: Field) -> Result<&str, StudioError> {
        let listing = self.listing()?;
        match field {
            Field::Path => Ok(&listing.path),
            Field::Parent => listing.parent.as_deref().ok_or_else(wrong),
            Field::Cursor => listing.next_cursor.as_deref().ok_or_else(wrong),
            Field::Name(index) => Ok(&listing.entries.get(index).ok_or_else(wrong)?.name),
            Field::EntryPath(index) => Ok(&listing.entries.get(index).ok_or_else(wrong)?.path),
        }
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown Remote directory page, field or offset")
}
