//! Image snapshots and decoding limits supplied by the host, independent of model protocols.

mod thread;
pub use thread::{
    ThreadViewImageTool, VIEW_IMAGE_RECEIPT_FORMAT, VIEW_IMAGE_RECEIPT_VERSION, ViewImageReceipt,
    saved_view_image_receipt,
};

pub use pl_tool_media::ImageOutputLimits;
pub use pl_tool_view_image::{Input as ViewImageInput, NAME as TOOL_VIEW_IMAGE};

pub use thread::thread_view_image_tool_definition;
