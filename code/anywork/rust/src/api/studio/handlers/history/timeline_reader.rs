//! 独立历史查询能力：捕获同一 Session，封闭准入后等待真实在途读取结束。

use std::sync::Mutex;

use pl_studio_runtime::TimelineContentReader;
use tokio_util::task::TaskTracker;

#[cfg(test)]
mod tests;

use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::timeline_content,
    types::{
        BridgeError, BridgeTimelineDetailChunk, BridgeTimelineDetailQuery, BridgeTimelinePage,
    },
};

#[flutter_rust_bridge::frb(opaque)]
pub struct BridgeTimelineReader {
    thread_id: String,
    timeline_epoch: String,
    reader: Mutex<Option<TimelineContentReader>>,
    queries: TaskTracker,
    #[cfg(test)]
    after_query: Mutex<Option<tests::QueryGate>>,
}

/// 打开只读能力不声明 feed 或执行需求；冷会话同样沿正式存储 preparation 准入。
pub async fn open_timeline_reader(thread_id: String) -> Result<BridgeTimelineReader, BridgeError> {
    let bridge = active_bridge().await?;
    let reader = bridge.studio.timeline_reader(&thread_id).await?;
    Ok(BridgeTimelineReader {
        thread_id,
        timeline_epoch: reader.epoch(),
        reader: Mutex::new(Some(reader)),
        queries: TaskTracker::new(),
        #[cfg(test)]
        after_query: Mutex::new(None),
    })
}

impl BridgeTimelineReader {
    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn timeline_epoch(&self) -> String {
        self.timeline_epoch.clone()
    }

    pub async fn page(
        &self,
        before: Option<String>,
        limit: Option<u32>,
    ) -> Result<BridgeTimelinePage, BridgeError> {
        // Pattern bindings drop in reverse order: release the Session clone before
        // the tracker token can wake close(), including error and cancellation.
        let (_query, reader) = {
            let guard = self
                .reader
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let reader = guard.as_ref().ok_or_else(closed)?.clone();
            // Token creation and admission sealing share this same short lock.
            (self.queries.token(), reader)
        };
        let page = reader
            .page(&pl_protocol::TimelinePageQuery { before, limit })
            .await?;
        #[cfg(test)]
        self.after_query().await;
        Ok(timeline_content::page(page))
    }

    pub async fn read_detail(
        &self,
        item_id: String,
        query: BridgeTimelineDetailQuery,
    ) -> Result<BridgeTimelineDetailChunk, BridgeError> {
        let (_query, reader) = {
            let guard = self
                .reader
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner);
            let reader = guard.as_ref().ok_or_else(closed)?.clone();
            (self.queries.token(), reader)
        };
        let query = timeline_content::detail_query(query);
        let chunk = reader.read_detail(&item_id, &query).await?;
        #[cfg(test)]
        self.after_query().await;
        Ok(timeline_content::detail_chunk(chunk))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        let mut guard = self
            .reader
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        guard.take();
        self.queries.close();
    }

    /// 可取消并重试等待；完成返回时全部受理查询的 Future 已结束并释放 Session 引用。
    pub async fn close(&self) {
        self.request_close();
        self.queries.wait().await;
    }
}

impl Drop for BridgeTimelineReader {
    fn drop(&mut self) {
        self.request_close();
    }
}

fn closed() -> BridgeError {
    pl_protocol::studio::StudioError::new(
        pl_protocol::studio::StudioErrorCode::Cancelled,
        "The timeline query scope is closed",
        false,
    )
    .into()
}
