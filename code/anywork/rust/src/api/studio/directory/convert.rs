use super::types::*;
use crate::api::studio::{convert::thread_stream::bridge_thread, types::BridgeResourceStamp};
use pl_protocol::studio as p;

impl From<BridgeThreadDirectoryQuery> for p::ThreadDirectoryQuery {
    fn from(value: BridgeThreadDirectoryQuery) -> Self {
        Self {
            workspace_id: value.workspace_id,
            search: value.search,
            archived: value.archived,
            filter: match value.filter {
                BridgeThreadDirectoryFilter::All => p::ThreadDirectoryFilter::All,
                BridgeThreadDirectoryFilter::Running => p::ThreadDirectoryFilter::Running,
                BridgeThreadDirectoryFilter::Attention => p::ThreadDirectoryFilter::Attention,
            },
            thread_ids: value.thread_ids,
            excluded_thread_ids: value.excluded_thread_ids,
        }
    }
}

impl From<BridgeThreadDirectoryWindow> for p::ThreadDirectoryWindow {
    fn from(value: BridgeThreadDirectoryWindow) -> Self {
        Self {
            before: value.before,
            limit: value.limit,
        }
    }
}

fn stamp(value: p::ResourceStamp) -> BridgeResourceStamp {
    BridgeResourceStamp {
        resource_key: value.resource_key,
        owner_epoch: value.owner_epoch,
        revision: value.revision,
    }
}

pub(crate) fn directory_frame(value: p::ThreadDirectoryFrame) -> BridgeThreadDirectoryFrame {
    BridgeThreadDirectoryFrame {
        query: BridgeThreadDirectoryQuery {
            workspace_id: value.query.workspace_id,
            search: value.query.search,
            archived: value.query.archived,
            filter: match value.query.filter {
                p::ThreadDirectoryFilter::All => BridgeThreadDirectoryFilter::All,
                p::ThreadDirectoryFilter::Running => BridgeThreadDirectoryFilter::Running,
                p::ThreadDirectoryFilter::Attention => BridgeThreadDirectoryFilter::Attention,
            },
            thread_ids: value.query.thread_ids,
            excluded_thread_ids: value.query.excluded_thread_ids,
        },
        window: BridgeThreadDirectoryWindow {
            before: value.window.before,
            limit: value.window.limit,
        },
        stamp: stamp(value.stamp),
        threads: value.threads.into_iter().map(bridge_thread).collect(),
        next_cursor: value.next_cursor,
    }
}

pub(crate) fn metadata_frame(value: p::ThreadMetadataFrame) -> BridgeThreadMetadataFrame {
    BridgeThreadMetadataFrame {
        thread_id: value.thread_id,
        stamp: stamp(value.stamp),
        thread: value.thread.map(bridge_thread),
    }
}
