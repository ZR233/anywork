//! 产品无关的 account、模型目录与动态角色路由配置。

mod account;
mod auth;
mod catalog;
mod descriptor;
mod model_catalog;
mod route;

pub use account::*;
pub use auth::*;
pub use catalog::*;
pub use descriptor::*;
pub use pl_model_types::config::*;
pub use route::*;
