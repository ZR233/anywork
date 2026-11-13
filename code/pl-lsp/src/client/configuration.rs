use lsp_types::{
    CallHierarchyClientCapabilities, ClientCapabilities, ConfigurationParams,
    DocumentSymbolClientCapabilities, GeneralClientCapabilities, GotoCapability,
    HoverClientCapabilities, InitializeParams, MarkupKind, PositionEncodingKind,
    PublishDiagnosticsClientCapabilities, ReferenceClientCapabilities,
    TextDocumentClientCapabilities, WindowClientCapabilities, WorkDoneProgressParams,
    WorkspaceClientCapabilities, WorkspaceFolder,
};
use serde_json::Value;

use super::uri::file_uri;
use crate::driver::LspServerDriver;
use crate::runtime::{LspResult, ResolvedLspServer};

pub(crate) fn initialize_params(
    server: &ResolvedLspServer,
    initialization_options: Value,
    style: crate::host::LspPathStyle,
) -> LspResult<Value> {
    let workspace = workspace_folder(server, style)?;
    #[allow(deprecated)]
    let params = InitializeParams {
        process_id: None,
        root_path: Some(server.workspace_root.display().to_string()),
        root_uri: Some(workspace.uri.clone()),
        initialization_options: Some(initialization_options),
        capabilities: client_capabilities(),
        workspace_folders: Some(vec![workspace]),
        work_done_progress_params: WorkDoneProgressParams::default(),
        ..InitializeParams::default()
    };
    Ok(serde_json::to_value(params)?)
}

pub(super) fn workspace_folder(
    server: &ResolvedLspServer,
    style: crate::host::LspPathStyle,
) -> LspResult<WorkspaceFolder> {
    Ok(WorkspaceFolder {
        uri: file_uri(&server.workspace_root, style)?,
        name: server
            .workspace_root
            .file_name()
            .and_then(|name| name.to_str())
            .unwrap_or("workspace")
            .to_string(),
    })
}

pub(crate) fn workspace_configuration_response(
    params: ConfigurationParams,
    driver: &dyn LspServerDriver,
) -> Value {
    Value::Array(
        params
            .items
            .iter()
            .map(|item| driver.configuration_response(item.section.as_deref()))
            .collect(),
    )
}

fn client_capabilities() -> ClientCapabilities {
    ClientCapabilities {
        window: Some(WindowClientCapabilities {
            work_done_progress: Some(true),
            ..WindowClientCapabilities::default()
        }),
        workspace: Some(WorkspaceClientCapabilities {
            configuration: Some(true),
            workspace_folders: Some(true),
            ..WorkspaceClientCapabilities::default()
        }),
        text_document: Some(TextDocumentClientCapabilities {
            publish_diagnostics: Some(PublishDiagnosticsClientCapabilities::default()),
            hover: Some(HoverClientCapabilities {
                content_format: Some(vec![MarkupKind::Markdown]),
                ..HoverClientCapabilities::default()
            }),
            definition: Some(GotoCapability::default()),
            references: Some(ReferenceClientCapabilities::default()),
            document_symbol: Some(DocumentSymbolClientCapabilities::default()),
            implementation: Some(GotoCapability::default()),
            call_hierarchy: Some(CallHierarchyClientCapabilities {
                dynamic_registration: Some(false),
            }),
            ..TextDocumentClientCapabilities::default()
        }),
        general: Some(GeneralClientCapabilities {
            position_encodings: Some(vec![PositionEncodingKind::UTF16]),
            ..GeneralClientCapabilities::default()
        }),
        ..ClientCapabilities::default()
    }
}
