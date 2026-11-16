use pl_studio_runtime::{
    ProductEventBus, ProductTopicReceiver, ProductTopicRecvError, ProductTopicTryRecvError,
    StudioProductEventEnvelope, StudioProductTopic,
};

#[test]
fn public_topic_receiver_and_errors_are_available_from_the_crate_facade() {
    let _: fn(&ProductEventBus, &StudioProductTopic) -> ProductTopicReceiver =
        ProductEventBus::subscribe_topic;
    let _ = ProductTopicReceiver::recv;
    let _: fn(
        &mut ProductTopicReceiver,
    ) -> Result<StudioProductEventEnvelope, ProductTopicTryRecvError> =
        ProductTopicReceiver::try_recv;

    // These are exact re-exports, not lookalike error enums or string conversions.
    let original_recv: tokio::sync::broadcast::error::RecvError = ProductTopicRecvError::Lagged(7);
    let exposed_recv: ProductTopicRecvError = tokio::sync::broadcast::error::RecvError::Closed;
    assert_eq!(
        original_recv,
        tokio::sync::broadcast::error::RecvError::Lagged(7)
    );
    assert_eq!(exposed_recv, ProductTopicRecvError::Closed);
    let original_try: tokio::sync::broadcast::error::TryRecvError = ProductTopicTryRecvError::Empty;
    let exposed_try: ProductTopicTryRecvError =
        tokio::sync::broadcast::error::TryRecvError::Lagged(5);
    assert_eq!(
        original_try,
        tokio::sync::broadcast::error::TryRecvError::Empty
    );
    assert_eq!(exposed_try, ProductTopicTryRecvError::Lagged(5));
}
