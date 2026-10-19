//! Provider-backed image generation archived as Thread media, without workspace writes.
//!
//! 该模块属于工具执行边界：provider 选择、凭据与目录观察由装配方完成，工具只消费一个
//! 已冻结的 Images 客户端、模型 slug 与媒体托管端口。生成的图片只经工具媒体归档进入
//! 资源；是否作为附件在时间线展示由 prepared 模型的图片输入能力与产品投影决定。工具不
//! 写工作区文件，也不建立第二份媒体事实源。

mod thread;

/// Stable tool identity shared with the product declaration and the receipt format.
pub const TOOL_IMAGE_GENERATION: &str = "generate_image";
/// Versioned receipt format emitted for one archived generated image.
pub const IMAGE_GENERATION_RECEIPT_FORMAT: &str = "pl.tool.image-generation";
/// Receipt layout version; changes require an explicit decoder update.
pub const IMAGE_GENERATION_RECEIPT_VERSION: u32 = 1;

pub use thread::{ImageGenerationInput, ImageGenerationReceipt, ThreadImageGenerationTool};
