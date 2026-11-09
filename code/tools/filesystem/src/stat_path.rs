//! Path metadata and absence, without exposing a file-reading tool.
use crate::StatRequest;
pub use crate::{PathInput, StatBackend};
use pl_agent_tool::typed::TypedTool;
use std::marker::PhantomData;

#[derive(Debug, PartialEq, Eq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct StatReceipt {
    pub path: String,
    pub exists: bool,
    #[serde(rename = "type", skip_serializing_if = "Option::is_none")]
    pub kind: Option<&'static str>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub len: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub readonly: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub modified_at: Option<i64>,
}

#[derive(Debug, Default)]
pub struct StatPathTool<B>(PhantomData<fn() -> B>);
impl<B> StatPathTool<B> {
    pub fn new() -> Self {
        Self(PhantomData)
    }
}
impl<B: StatBackend + 'static> TypedTool for StatPathTool<B> {
    const NAME: &'static str = "stat_path";
    const DESCRIPTION: &'static str =
        "Return metadata for a workspace path, or exists: false when the path is absent.";
    type Args = PathInput;
    type Context = B;
    type Output = StatReceipt;
    type Error = B::Error;

    async fn execute(&self, input: Self::Args, backend: B) -> Result<StatReceipt, B::Error> {
        Ok(
            match backend
                .stat_optional(StatRequest {
                    path: input.path.clone(),
                    cwd: None,
                })
                .await?
            {
                Some(stat) => StatReceipt {
                    path: stat.path,
                    exists: true,
                    kind: Some(if stat.is_file {
                        "file"
                    } else if stat.is_dir {
                        "directory"
                    } else {
                        "other"
                    }),
                    len: stat.len,
                    readonly: stat.readonly,
                    modified_at: stat.modified_at,
                },
                None => StatReceipt {
                    path: input.path,
                    exists: false,
                    kind: None,
                    len: None,
                    readonly: None,
                    modified_at: None,
                },
            },
        )
    }
}

pub fn definition<B: StatBackend + 'static>() -> pl_agent_tool::ToolDefinition {
    pl_agent_tool::typed::prepare_json::<StatPathTool<B>>()
        .expect("static file tool definition")
        .definition()
        .clone()
}
