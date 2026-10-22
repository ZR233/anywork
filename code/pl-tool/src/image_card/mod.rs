//! Timeline image display of an image this Thread already archived, without new bytes.
//!
//! 该模块属于工具执行边界：它只从本次调用已冻结的上下文中挑出一份已归档图片引用，并写入带
//! 有界展示文案的版本化回执。工具不持有媒体 host、不 retain 字节、不读工作区文件，也不扩大
//! pl-model / pl-core 的公共接口。图片字节始终由资源与附件缓存按身份读取，产品投影负责把该
//! 引用变成时间线卡片（见 design/06 §6.13 与 design/09 §9.1）。

mod thread;

/// Stable tool identity shared with the product declaration and the receipt format.
pub const TOOL_SHOW_IMAGE: &str = "show_image";
/// Versioned receipt format emitted for one displayed image card.
pub const IMAGE_CARD_FORMAT: &str = "pl.tool.image-card";
/// Receipt layout version; changes require an explicit decoder update.
pub const IMAGE_CARD_VERSION: u32 = 1;

pub use thread::{ImageCardReceipt, ShowImageInput, ThreadShowImageTool, saved_image_card_receipt};
