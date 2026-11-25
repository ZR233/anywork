//! Feishu binding and the original send ledger's two-stage file delivery.
mod driver;
mod port;

pub(crate) use driver::{
    FileDeliveryFact, deliver, initial_record, local_error, resumable, validate_record,
};
pub(super) use port::feishu_reply_binding;

#[cfg(test)]
mod tests;
