//! 产品事件的 topic 通道注册与分发路由。
//!
//! 每个订阅者只登记自己声明的 topic；事件按 [`StudioProductTopic::of_kind`] 路由到
//! 对应通道，无关领域既不进入订阅者缓冲，也不占用该 topic 的容量。通道不持有业务
//! 投影，只转发 owner 发布的同一 canonical envelope。

use std::collections::BTreeMap;
use std::sync::{Arc, Mutex, Weak};

use tokio::sync::{broadcast, watch};

use crate::{StudioProductEventEnvelope, StudioProductTopic};

pub use tokio::sync::broadcast::error::{
    RecvError as ProductTopicRecvError, TryRecvError as ProductTopicTryRecvError,
};

/// 单个 topic 通道的容量；与订阅者消费速率无关的进程内环形缓冲。
const TOPIC_CHANNEL_CAPACITY: usize = 256;

/// 代次保护的 sender 表。旧凭证只能回收自己登记的那一代。
#[derive(Debug)]
pub(in crate::studio::product_event_bus) struct TopicMap<S, K = StudioProductTopic> {
    entries: BTreeMap<K, TopicEntry<S>>,
    generation: u64,
}

pub(in crate::studio::product_event_bus) struct TopicLease<K> {
    key: K,
    generation: u64,
}

impl<K> TopicLease<K> {
    #[cfg(test)]
    pub(in crate::studio::product_event_bus) fn generation(&self) -> u64 {
        self.generation
    }
}

pub(in crate::studio::product_event_bus) trait TopicSender:
    Sized
{
    type Receiver;
    fn open() -> Self;
    fn receiver_count(&self) -> usize;
    fn attach(&self) -> Self::Receiver;
}

impl TopicSender for broadcast::Sender<StudioProductEventEnvelope> {
    type Receiver = broadcast::Receiver<StudioProductEventEnvelope>;

    fn open() -> Self {
        broadcast::channel(TOPIC_CHANNEL_CAPACITY).0
    }

    fn receiver_count(&self) -> usize {
        broadcast::Sender::receiver_count(self)
    }

    fn attach(&self) -> Self::Receiver {
        broadcast::Sender::subscribe(self)
    }
}

impl TopicSender for watch::Sender<()> {
    type Receiver = watch::Receiver<()>;

    fn open() -> Self {
        watch::channel(()).0
    }

    fn receiver_count(&self) -> usize {
        watch::Sender::receiver_count(self)
    }

    fn attach(&self) -> Self::Receiver {
        watch::Sender::subscribe(self)
    }
}

impl<S, K> Default for TopicMap<S, K> {
    fn default() -> Self {
        Self {
            entries: BTreeMap::new(),
            generation: 0,
        }
    }
}

impl<S, K> TopicMap<S, K>
where
    K: Clone + Ord,
    S: TopicSender,
{
    pub(in crate::studio::product_event_bus) fn subscribe(
        &mut self,
        key: K,
    ) -> (S::Receiver, TopicLease<K>) {
        if !self.entries.contains_key(&key) {
            let generation = self.next_generation();
            self.entries.insert(
                key.clone(),
                TopicEntry {
                    generation,
                    sender: S::open(),
                },
            );
        }
        let entry = self.entries.get(&key).expect("registered topic");
        let receiver = entry.sender.attach();
        let generation = entry.generation;
        (receiver, TopicLease { key, generation })
    }

    pub(in crate::studio::product_event_bus) fn reclaim(&mut self, lease: &TopicLease<K>) {
        if self.entries.get(&lease.key).is_some_and(|entry| {
            entry.generation == lease.generation && entry.sender.receiver_count() == 0
        }) {
            self.entries.remove(&lease.key);
        }
    }

    #[cfg(test)]
    pub(in crate::studio::product_event_bus) fn len(&self) -> usize {
        self.entries.len()
    }

    pub(in crate::studio::product_event_bus) fn contains(&self, key: &K) -> bool {
        self.entries.contains_key(key)
    }

    pub(in crate::studio::product_event_bus) fn sender(&self, key: &K) -> Option<&S> {
        self.entries.get(key).map(|entry| &entry.sender)
    }

    fn remove(&mut self, key: &K) {
        self.entries.remove(key);
    }

    fn next_generation(&mut self) -> u64 {
        self.generation = self
            .generation
            .checked_add(1)
            .expect("topic registration generation exhausted");
        self.generation
    }
}

impl<K: Ord> TopicMap<watch::Sender<()>, K> {
    /// 没有接收者时回收空通道；否则只发布最新唤醒，不积压业务值。
    pub(in crate::studio::product_event_bus) fn wake<Q>(&mut self, key: &Q)
    where
        K: std::borrow::Borrow<Q>,
        Q: Ord + ?Sized,
    {
        let idle = self
            .entries
            .get(key)
            .is_some_and(|entry| entry.sender.receiver_count() == 0);
        if idle {
            self.entries.remove(key);
            return;
        }
        if let Some(entry) = self.entries.get(key) {
            entry.sender.send_replace(());
        }
    }
}

/// 一个独占的产品主题接收凭证。
///
/// 丢弃凭证先释放接收者，再回收同一登记代次中已无需求的通知通道；不持有产品总线或
/// 领域 owner。取消一次 [`Self::recv`] 等待不会释放凭证，也不会消费尚未交付的事件。
/// 通道没有 durable replay；重新订阅后须读取当前领域基线。
pub struct ProductTopicReceiver {
    receiver: Option<broadcast::Receiver<StudioProductEventEnvelope>>,
    registration: TopicLease<StudioProductTopic>,
    registry: Weak<Mutex<TopicChannels>>,
}

impl ProductTopicReceiver {
    /// 等待下一条事件；保留 Tokio 原始的关闭与滞后错误及其类型身份。
    pub async fn recv(&mut self) -> Result<StudioProductEventEnvelope, ProductTopicRecvError> {
        self.receiver
            .as_mut()
            .expect("live product topic registration")
            .recv()
            .await
    }

    /// 不等待地领取下一条事件；空缓冲、关闭和滞后分别返回原始 Tokio 错误。
    pub fn try_recv(&mut self) -> Result<StudioProductEventEnvelope, ProductTopicTryRecvError> {
        self.receiver
            .as_mut()
            .expect("live product topic registration")
            .try_recv()
    }
}

impl Drop for ProductTopicReceiver {
    fn drop(&mut self) {
        drop(self.receiver.take());
        reclaim_registration(&self.registry, |channels| {
            channels.channels.reclaim(&self.registration);
        });
    }
}

/// 只唤醒按需查询的独占登记凭证，不存业务值或事件积压。
pub(crate) struct ProductTopicSignal {
    receiver: Option<watch::Receiver<()>>,
    registration: TopicLease<StudioProductTopic>,
    registry: Weak<Mutex<TopicChannels>>,
}

impl ProductTopicSignal {
    pub(crate) async fn changed(&mut self) -> Result<(), watch::error::RecvError> {
        self.receiver
            .as_mut()
            .expect("live product topic signal registration")
            .changed()
            .await
    }

    /// 在读取领域状态之前消费当前唤醒，使读取期间发生的变化仍保留为未读。
    pub(crate) fn mark_current(&mut self) {
        self.receiver
            .as_mut()
            .expect("live product topic signal registration")
            .borrow_and_update();
    }
}

impl Drop for ProductTopicSignal {
    fn drop(&mut self) {
        drop(self.receiver.take());
        reclaim_registration(&self.registry, |channels| {
            channels.signals.reclaim(&self.registration);
        });
    }
}

fn reclaim_registration(
    registry: &Weak<Mutex<TopicChannels>>,
    cleanup: impl FnOnce(&mut TopicChannels),
) {
    let Some(registry) = registry.upgrade() else {
        return;
    };
    let mut registry = registry
        .lock()
        .unwrap_or_else(std::sync::PoisonError::into_inner);
    cleanup(&mut registry);
}

#[derive(Debug)]
struct TopicEntry<S> {
    generation: u64,
    sender: S,
}

/// topic → 通道的惰性注册表。
///
/// `emit` 只向已存在的通道发送；没有任何订阅者的 topic 不保留事件（无 durable
/// replay），新订阅者通过首帧基线取得当前事实。
#[derive(Debug, Default)]
pub(super) struct TopicChannels {
    channels: TopicMap<broadcast::Sender<StudioProductEventEnvelope>>,
    signals: TopicMap<watch::Sender<()>>,
}

impl TopicChannels {
    /// Wake-only latest-state observation: no business payload and no event backlog.
    pub(super) fn subscribe_signal(
        registry: &Arc<Mutex<Self>>,
        topic: &StudioProductTopic,
    ) -> ProductTopicSignal {
        let mut channels = registry
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (receiver, registration) = channels.signals.subscribe(topic.clone());
        ProductTopicSignal {
            receiver: Some(receiver),
            registration,
            registry: Arc::downgrade(registry),
        }
    }

    /// 订阅一个 topic；通道不存在时以固定容量创建。
    pub(super) fn subscribe(
        registry: &Arc<Mutex<Self>>,
        topic: &StudioProductTopic,
    ) -> ProductTopicReceiver {
        let mut channels = registry
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let (receiver, registration) = channels.channels.subscribe(topic.clone());
        ProductTopicReceiver {
            receiver: Some(receiver),
            registration,
            registry: Arc::downgrade(registry),
        }
    }

    /// 把 envelope 只投递到它所属的 topic 通道。
    ///
    /// 通道没有订阅者或已关闭时丢弃；`sequence` 是全局序列，消费端按领域 revision
    /// 判断新旧，因此同一通道内序列不连续不是 lag。
    pub(super) fn dispatch(&mut self, envelope: &StudioProductEventEnvelope) {
        let topic = StudioProductTopic::of_kind(&envelope.kind);
        self.notify(&topic);
        if let Some(sender) = self.channels.sender(&topic)
            && sender.send(envelope.clone()).is_err()
        {
            self.channels.remove(&topic);
        }
    }

    /// A query dependency can change without a Thread row delta.
    pub(super) fn notify(&mut self, topic: &StudioProductTopic) {
        self.signals.wake(topic);
    }
}

#[cfg(test)]
impl super::ProductEventBus {
    pub(crate) fn topic_registration_counts(&self) -> (usize, usize) {
        let channels = self.topics.lock().unwrap();
        (channels.channels.len(), channels.signals.len())
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::StudioProductEventKind;
    use futures::FutureExt;

    fn registry() -> Arc<Mutex<TopicChannels>> {
        Arc::default()
    }

    fn counts(registry: &Mutex<TopicChannels>) -> (usize, usize) {
        let registry = registry.lock().unwrap();
        (registry.channels.len(), registry.signals.len())
    }

    fn envelope(sequence: u64) -> StudioProductEventEnvelope {
        StudioProductEventEnvelope {
            event_id: format!("topic-test-{sequence}"),
            sequence,
            created_at: 1,
            kind: StudioProductEventKind::ThreadDirectoryChanged(
                crate::StudioThreadDirectoryDelta {
                    revision: sequence,
                    updated_at: 1,
                    upserted: vec![],
                    removed: vec![],
                },
            ),
        }
    }

    #[test]
    fn dynamic_thread_and_workspace_topics_return_to_original_cardinality() {
        let registry = registry();
        let stable_receiver =
            TopicChannels::subscribe(&registry, &StudioProductTopic::ThreadDirectory);
        let stable_signal =
            TopicChannels::subscribe_signal(&registry, &StudioProductTopic::ThreadDirectory);
        let baseline = counts(&registry);
        let mut receivers = Vec::new();
        let mut signals = Vec::new();
        for index in 0..128 {
            for topic in [
                StudioProductTopic::ThreadLsp {
                    thread_id: format!("thread-{index}"),
                },
                StudioProductTopic::Skills {
                    workspace_id: format!("workspace-{index}"),
                },
            ] {
                receivers.push(TopicChannels::subscribe(&registry, &topic));
                signals.push(TopicChannels::subscribe_signal(&registry, &topic));
            }
        }
        assert_eq!(counts(&registry), (baseline.0 + 256, baseline.1 + 256));
        assert_eq!(
            Arc::strong_count(&registry),
            1,
            "credentials only borrow the registry weakly"
        );
        drop(receivers);
        drop(signals);
        assert_eq!(counts(&registry), baseline);
        drop(stable_receiver);
        drop(stable_signal);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[tokio::test]
    async fn only_last_receiver_reclaims_its_channel_kind() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let first = TopicChannels::subscribe(&registry, &topic);
        let mut second = TopicChannels::subscribe(&registry, &topic);
        let first_signal = TopicChannels::subscribe_signal(&registry, &topic);
        let mut second_signal = TopicChannels::subscribe_signal(&registry, &topic);
        drop(first);
        drop(first_signal);
        assert_eq!(counts(&registry), (1, 1));
        let first_event = envelope(1);
        registry.lock().unwrap().dispatch(&first_event);
        assert_eq!(second.try_recv().unwrap(), first_event);
        assert!(matches!(
            second_signal.changed().now_or_never(),
            Some(Ok(()))
        ));

        drop(second);
        assert_eq!(counts(&registry), (0, 1));
        registry.lock().unwrap().dispatch(&envelope(2));
        assert!(matches!(
            second_signal.changed().now_or_never(),
            Some(Ok(()))
        ));
        drop(second_signal);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[test]
    fn dispatch_and_notify_neither_create_nor_keep_receiverless_entries() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        {
            let mut channels = registry.lock().unwrap();
            channels.dispatch(&envelope(1));
            channels.notify(&topic);
            assert_eq!(
                (channels.channels.generation, channels.signals.generation),
                (0, 0),
                "publishing does not allocate registrations"
            );
        }
        assert_eq!(counts(&registry), (0, 0));
        let mut receiver = TopicChannels::subscribe(&registry, &topic);
        let mut signal = TopicChannels::subscribe_signal(&registry, &topic);
        // Pause both Drops after their receiver-release step, before the registry lock.
        drop(receiver.receiver.take());
        drop(signal.receiver.take());
        assert_eq!(counts(&registry), (1, 1));
        registry.lock().unwrap().dispatch(&envelope(2));
        assert_eq!(counts(&registry), (0, 0));
        drop(receiver);
        drop(signal);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[test]
    fn resubscribe_before_old_drop_preserves_both_new_receivers() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let mut old = TopicChannels::subscribe(&registry, &topic);
        let mut old_signal = TopicChannels::subscribe_signal(&registry, &topic);
        drop(old.receiver.take());
        drop(old_signal.receiver.take());
        let mut replacement = TopicChannels::subscribe(&registry, &topic);
        let mut replacement_signal = TopicChannels::subscribe_signal(&registry, &topic);
        assert_eq!(
            replacement.registration.generation,
            old.registration.generation
        );
        assert_eq!(
            replacement_signal.registration.generation,
            old_signal.registration.generation
        );
        drop(old);
        drop(old_signal);
        assert_eq!(counts(&registry), (1, 1));
        registry.lock().unwrap().dispatch(&envelope(1));
        assert_eq!(replacement.try_recv().unwrap(), envelope(1));
        assert!(matches!(
            replacement_signal.changed().now_or_never(),
            Some(Ok(()))
        ));
        drop(replacement);
        drop(replacement_signal);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[test]
    fn delayed_broadcast_drop_cannot_reclaim_a_new_generation_in_aba_order() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let mut old = TopicChannels::subscribe(&registry, &topic);
        let old_generation = old.registration.generation;
        // Reproduce the reachable window between receiver Drop and registration cleanup.
        drop(old.receiver.take());
        registry.lock().unwrap().dispatch(&envelope(1));
        let unrelated = TopicChannels::subscribe(&registry, &StudioProductTopic::ProjectDirectory);
        let mut replacement = TopicChannels::subscribe(&registry, &topic);
        assert!(unrelated.registration.generation > old_generation);
        assert!(replacement.registration.generation > unrelated.registration.generation);
        registry.lock().unwrap().dispatch(&envelope(2));
        assert_eq!(replacement.try_recv().unwrap(), envelope(2));
        // The new receiver can itself be dropping. Count == 0 alone must not let the old Drop
        // remove its entry: only the matching generation owns that cleanup.
        drop(replacement.receiver.take());
        drop(old);
        assert_eq!(counts(&registry), (2, 0));
        drop(replacement);
        drop(unrelated);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[tokio::test]
    async fn delayed_signal_drop_cannot_reclaim_a_new_generation_in_aba_order() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let mut old = TopicChannels::subscribe_signal(&registry, &topic);
        let old_generation = old.registration.generation;
        drop(old.receiver.take());
        registry.lock().unwrap().notify(&topic);
        let unrelated =
            TopicChannels::subscribe_signal(&registry, &StudioProductTopic::ProjectDirectory);
        let mut replacement = TopicChannels::subscribe_signal(&registry, &topic);
        assert!(unrelated.registration.generation > old_generation);
        assert!(replacement.registration.generation > unrelated.registration.generation);
        registry.lock().unwrap().notify(&topic);
        assert!(matches!(replacement.changed().now_or_never(), Some(Ok(()))));
        drop(replacement.receiver.take());
        drop(old);
        assert_eq!(counts(&registry), (0, 2));
        drop(replacement);
        drop(unrelated);
        assert_eq!(counts(&registry), (0, 0));
    }

    #[tokio::test]
    async fn cancelled_waits_preserve_live_credentials_and_unread_notifications() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let mut receiver = TopicChannels::subscribe(&registry, &topic);
        let mut signal = TopicChannels::subscribe_signal(&registry, &topic);
        let mut receiving = Box::pin(receiver.recv());
        let mut changing = Box::pin(signal.changed());
        assert!(futures::poll!(receiving.as_mut()).is_pending());
        assert!(futures::poll!(changing.as_mut()).is_pending());
        // Cancellation happens after notification but before either wait is polled again.
        registry.lock().unwrap().dispatch(&envelope(1));
        drop(receiving);
        drop(changing);
        assert_eq!(counts(&registry), (1, 1));
        assert_eq!(
            receiver.recv().now_or_never().unwrap().unwrap(),
            envelope(1)
        );
        assert!(matches!(signal.changed().now_or_never(), Some(Ok(()))));

        signal.mark_current();
        registry.lock().unwrap().notify(&topic);
        assert!(matches!(signal.changed().now_or_never(), Some(Ok(()))));
    }

    #[tokio::test]
    async fn receiver_preserves_original_empty_lagged_and_closed_errors() {
        let registry = registry();
        let topic = StudioProductTopic::ThreadDirectory;
        let mut receiving = TopicChannels::subscribe(&registry, &topic);
        let mut trying = TopicChannels::subscribe(&registry, &topic);
        let mut signal = TopicChannels::subscribe_signal(&registry, &topic);
        assert_eq!(trying.try_recv(), Err(ProductTopicTryRecvError::Empty));
        for sequence in 1..=(TOPIC_CHANNEL_CAPACITY as u64 + 1) {
            registry.lock().unwrap().dispatch(&envelope(sequence));
        }
        assert_eq!(
            receiving.recv().await,
            Err(ProductTopicRecvError::Lagged(1))
        );
        assert_eq!(trying.try_recv(), Err(ProductTopicTryRecvError::Lagged(1)));
        for sequence in 2..=(TOPIC_CHANNEL_CAPACITY as u64 + 1) {
            assert_eq!(receiving.recv().await.unwrap(), envelope(sequence));
            assert_eq!(trying.try_recv().unwrap(), envelope(sequence));
        }
        signal.mark_current();
        let weak = Arc::downgrade(&registry);
        drop(registry);
        assert!(
            weak.upgrade().is_none(),
            "credentials must not retain the bus registry"
        );
        assert_eq!(receiving.recv().await, Err(ProductTopicRecvError::Closed));
        assert_eq!(trying.try_recv(), Err(ProductTopicTryRecvError::Closed));
        assert!(signal.changed().await.is_err());
    }

    #[tokio::test]
    async fn reclaiming_notifications_preserves_product_snapshot_revision_and_sequence()
    -> anyhow::Result<()> {
        use crate::studio::{StudioStore, agent_host::ThreadWriteBehindWriter};

        let temp = tempfile::tempdir()?;
        let store = StudioStore::open(temp.path().join("data/studio.sqlite")).await?;
        let writer = ThreadWriteBehindWriter::new(store.clone());
        let events = super::super::ProductEventBus::new(store.clone(), writer.clone());
        events.initialize_directories().await?;
        let project = crate::WorkspaceRecord {
            id: "registered-project".into(),
            kind: crate::WorkspaceKind::Project,
            name: "registered project".into(),
            path: temp.path().to_string_lossy().into_owned(),
            ssh_alias: None,
            updated_at: 1,
        };
        events.apply_project_delta(&[project], &[]).await?;
        let before = events.read_project_directory().await?;
        assert!(before.state.revision() > 0);
        assert_eq!(before.state.value().unwrap().projects.len(), 1);
        let receiver = events.subscribe_topic(&StudioProductTopic::ProjectDirectory);
        let signal = events.subscribe_topic_signal(&StudioProductTopic::ProjectDirectory);
        let published = events.emit(StudioProductEventKind::ProjectDirectoryChanged(
            before.clone(),
        ));
        drop(receiver);
        drop(signal);
        assert_eq!(events.topic_registration_counts(), (0, 0));
        assert_eq!(events.read_project_directory().await?, before);
        assert_eq!(events.current_sequence(), published.sequence);
        let mut resubscribed = events.subscribe_topic(&StudioProductTopic::ProjectDirectory);
        assert_eq!(
            resubscribed.try_recv(),
            Err(ProductTopicTryRecvError::Empty)
        );
        assert_eq!(events.read_project_directory().await?, before);
        drop(resubscribed);
        writer.shutdown().await?;
        store.close().await?;
        Ok(())
    }
}
