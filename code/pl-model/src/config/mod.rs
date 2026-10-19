//! 产品无关的 account、模型目录与动态角色路由配置。

mod account;
mod catalog;
mod id;
mod model_catalog;
mod route;

pub use pl_protocol::ModelDescriptor;

pub use account::*;
pub use catalog::*;
pub use id::*;
pub use route::*;
