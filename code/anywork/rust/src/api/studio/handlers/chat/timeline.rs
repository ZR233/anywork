//! Independent FRB owners for immutable History and mutable Current reads.

use std::sync::atomic::{AtomicU64, Ordering};

use crate::api::studio::{
    bridge_runtime::active_bridge,
    convert::{chat, presentation},
    subscription::{error::open_error, factory::BridgeObservationFactory},
    types::*,
};
use pl_lifecycle::{Managed, ManagedResource};
use pl_studio_runtime::{CurrentReader, history::HistoryReader};

static READER_SEQUENCE: AtomicU64 = AtomicU64::new(0);

fn next_reader_id(kind: &str, thread_id: &str) -> String {
    let sequence = READER_SEQUENCE.fetch_add(1, Ordering::Relaxed);
    format!("{kind}:{thread_id}:{sequence}")
}

struct HistoryResource(HistoryReader);
impl ManagedResource for HistoryResource {
    type Error = BridgeError;

    fn request_close(&self) {
        self.0.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        self.0.close().await;
        Ok(())
    }
}

struct CurrentResource(CurrentReader);
impl ManagedResource for CurrentResource {
    type Error = BridgeError;

    fn request_close(&self) {
        self.0.request_close();
    }

    async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.0.close().await?)
    }
}

pub struct BridgeHistoryReader {
    reader_id: String,
    thread_id: String,
    managed: Managed<HistoryResource>,
}

pub async fn open_history_reader(
    thread_id: String,
    history_protocol_version: u32,
) -> Result<BridgeHistoryReader, BridgeError> {
    let bridge = active_bridge().await?;
    bridge
        .observation_factory
        .open_history(thread_id, history_protocol_version)
        .await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_history(
        &self,
        thread_id: String,
        history_protocol_version: u32,
    ) -> Result<BridgeHistoryReader, BridgeError> {
        let source = self.source.clone();
        let identity = thread_id.clone();
        let managed = self
            .scope
            .open("history", move |_| async move {
                let reader = source
                    .open_history_reader(&thread_id, history_protocol_version)
                    .await?;
                Ok(HistoryResource(reader))
            })
            .await
            .map_err(open_error)?;
        let reader_id = next_reader_id("history", &identity);
        Ok(BridgeHistoryReader {
            reader_id,
            thread_id: identity,
            managed,
        })
    }
}

impl BridgeHistoryReader {
    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn metadata(&self) -> Result<BridgeOpenHistoryReader, BridgeError> {
        Ok(BridgeOpenHistoryReader {
            reader_id: self.reader_id.clone(),
            history_protocol_version: BRIDGE_HISTORY_PROTOCOL_VERSION,
        })
    }

    pub async fn capture(&self) -> Result<BridgeHistoryCut, BridgeError> {
        Ok(presentation::cut_to_bridge(
            self.managed.get().0.capture().await?,
        ))
    }

    pub async fn timeline_page(
        &self,
        cut: Option<BridgeHistoryCut>,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryTimelinePage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .timeline_page(
                cut.map(presentation::bridge_to_cut),
                cursor,
                presentation::history_demand(demand),
            )
            .await?;
        Ok(presentation::timeline_page(page))
    }

    pub async fn group_page(
        &self,
        group_id: String,
        cut: Option<BridgeHistoryCut>,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryGroupPage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .group_page(
                group_id,
                cut.map(presentation::bridge_to_cut),
                cursor,
                presentation::history_demand(demand),
            )
            .await?;
        Ok(presentation::group_page(page))
    }

    pub async fn turns_page(
        &self,
        cut: Option<BridgeHistoryCut>,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryTimelinePage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .turns_page(
                cut.map(presentation::bridge_to_cut),
                cursor,
                presentation::history_demand(demand),
            )
            .await?;
        Ok(presentation::timeline_page(page))
    }

    pub async fn events_page(
        &self,
        query: BridgeHistoryEventsQuery,
        cut: Option<BridgeHistoryCut>,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryEventsPage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .events_page(
                presentation::history_events_query(query),
                cut.map(presentation::bridge_to_cut),
                cursor,
                presentation::history_demand(demand),
            )
            .await?;
        Ok(presentation::events_page(page))
    }

    pub async fn read_event(
        &self,
        event_id: String,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryEventDetail, BridgeError> {
        let detail = self
            .managed
            .get()
            .0
            .read_event(event_id, presentation::history_demand(demand))
            .await?;
        Ok(presentation::event_detail(detail))
    }

    pub async fn list_bodies(
        &self,
        event_id: String,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryBodyPage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .list_bodies(event_id, cursor, presentation::history_demand(demand))
            .await?;
        Ok(presentation::body_page(page))
    }

    pub async fn read_body(
        &self,
        reference: BridgeHistoryEventBodyRef,
        offset: u64,
        max_bytes: u32,
    ) -> Result<BridgeHistoryBodyWindow, BridgeError> {
        let window = self
            .managed
            .get()
            .0
            .read_body(
                presentation::bridge_to_body_ref(reference),
                offset,
                max_bytes,
            )
            .await?;
        Ok(presentation::history_body_window(window))
    }

    pub async fn accounting(
        &self,
        cut: Option<BridgeHistoryCut>,
    ) -> Result<Option<BridgeHistoryAccounting>, BridgeError> {
        let head = self
            .managed
            .get()
            .0
            .accounting(cut.map(presentation::bridge_to_cut))
            .await?;
        Ok(head.map(presentation::accounting))
    }

    pub async fn costs_page(
        &self,
        cut: Option<BridgeHistoryCut>,
        cursor: Option<String>,
        demand: BridgeHistoryDemand,
    ) -> Result<BridgeHistoryTimelinePage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .costs_page(
                cut.map(presentation::bridge_to_cut),
                cursor,
                presentation::history_demand(demand),
            )
            .await?;
        Ok(presentation::timeline_page(page))
    }

    pub async fn wait_changed(
        &self,
        after: BridgeHistoryCut,
    ) -> Result<BridgeHistoryCut, BridgeError> {
        let changed = self
            .managed
            .get()
            .0
            .wait_changed(presentation::bridge_to_cut(after))
            .await?;
        Ok(presentation::cut_to_bridge(changed))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.managed.get().0.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.managed.close().await?)
    }
}

pub struct BridgeCurrentReader {
    reader_id: String,
    thread_id: String,
    managed: Managed<CurrentResource>,
    initial_view: BridgeCurrentView,
}

pub async fn open_current_reader(
    thread_id: String,
    current_protocol_version: u32,
    demand: BridgeReadDemand,
) -> Result<BridgeCurrentReader, BridgeError> {
    let bridge = active_bridge().await?;
    bridge
        .observation_factory
        .open_current(thread_id, current_protocol_version, demand)
        .await
}

impl BridgeObservationFactory {
    pub(crate) async fn open_current(
        &self,
        thread_id: String,
        current_protocol_version: u32,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentReader, BridgeError> {
        let source = self.source.clone();
        let identity = thread_id.clone();
        let protocol_demand = presentation::read_demand(demand);
        let managed = self
            .scope
            .open("current", move |_| async move {
                let reader = source
                    .open_current_reader(&thread_id, current_protocol_version, protocol_demand)
                    .await?;
                Ok(CurrentResource(reader))
            })
            .await
            .map_err(open_error)?;
        let reader = &managed.get().0;
        let initial = presentation::current_view(reader.snapshot(protocol_demand).await?)?;
        let reader_id = next_reader_id("current", &identity);
        Ok(BridgeCurrentReader {
            reader_id,
            thread_id: identity,
            managed,
            initial_view: initial,
        })
    }
}

impl BridgeCurrentReader {
    #[flutter_rust_bridge::frb(sync)]
    pub fn thread_id(&self) -> String {
        self.thread_id.clone()
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn metadata(&self) -> BridgeOpenCurrentReader {
        BridgeOpenCurrentReader {
            reader_id: self.reader_id.clone(),
            current_protocol_version: BRIDGE_CURRENT_PROTOCOL_VERSION,
            current_owner_id: self.initial_view.revision.owner_id.clone(),
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn initial_view(&self) -> BridgeCurrentView {
        self.initial_view.clone()
    }

    pub async fn snapshot(
        &self,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentView, BridgeError> {
        let view = self
            .managed
            .get()
            .0
            .snapshot(presentation::read_demand(demand))
            .await?;
        Ok(presentation::current_view(view)?)
    }

    pub async fn watch(
        &self,
        after: Option<BridgeCurrentRevision>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentWatch, BridgeError> {
        let watch = self
            .managed
            .get()
            .0
            .watch(
                after.map(presentation::bridge_to_current_revision),
                presentation::read_demand(demand),
            )
            .await?;
        Ok(BridgeCurrentWatch { watch })
    }

    pub async fn page_collection(
        &self,
        reference: BridgeCurrentCollectionRef,
        continuation: Option<String>,
        demand: BridgeReadDemand,
    ) -> Result<BridgeCurrentCollectionPage, BridgeError> {
        let page = self
            .managed
            .get()
            .0
            .page_collection(
                presentation::bridge_to_current_collection_ref(reference),
                continuation,
                presentation::read_demand(demand),
            )
            .await?;
        Ok(presentation::current_collection_page(page))
    }

    pub async fn read_body(
        &self,
        reference: BridgeCurrentContentRef,
        range: BridgeContentRange,
    ) -> Result<BridgeContentWindow, BridgeError> {
        let window = self
            .managed
            .get()
            .0
            .read_body(
                presentation::bridge_to_current_content_ref(reference),
                chat::range(range),
            )
            .await?;
        Ok(chat::window(window))
    }

    pub async fn watch_body(
        &self,
        reference: BridgeCurrentContentRef,
        range: BridgeContentRange,
    ) -> Result<BridgeCurrentBodyWatch, BridgeError> {
        let watch = self
            .managed
            .get()
            .0
            .watch_body(
                presentation::bridge_to_current_content_ref(reference),
                chat::range(range),
            )
            .await?;
        Ok(BridgeCurrentBodyWatch { watch })
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.managed.get().0.request_close();
    }

    pub async fn close(&self) -> Result<(), BridgeError> {
        Ok(self.managed.close().await?)
    }
}

pub struct BridgeCurrentWatch {
    watch: pl_studio_runtime::CurrentWatch,
}

impl BridgeCurrentWatch {
    pub async fn next(&mut self) -> Result<Option<BridgeCurrentFrame>, BridgeError> {
        let frame = self.watch.next().await?;
        match frame {
            None => Ok(None),
            Some(frame) => Ok(Some(presentation::current_frame(frame)?)),
        }
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.watch.request_close();
    }

    pub async fn close(&mut self) -> Result<(), BridgeError> {
        Ok(self.watch.close().await?)
    }
}

pub struct BridgeCurrentBodyWatch {
    watch: pl_studio_runtime::CurrentBodyWatch,
}

impl BridgeCurrentBodyWatch {
    pub async fn next(&mut self) -> Result<Option<BridgeContentWindow>, BridgeError> {
        let window = self.watch.next().await?;
        Ok(window.map(chat::window))
    }

    #[flutter_rust_bridge::frb(sync)]
    pub fn request_close(&self) {
        self.watch.request_close();
    }

    pub async fn close(&mut self) -> Result<(), BridgeError> {
        Ok(self.watch.close().await?)
    }
}
