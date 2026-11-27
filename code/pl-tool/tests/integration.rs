#[allow(dead_code)]
#[path = "support/binding_host.rs"]
mod binding_host;
#[path = "integration/command_capture_limit.rs"]
mod command_capture_limit;
#[cfg(target_os = "linux")]
#[path = "integration/executor_binding.rs"]
mod executor_binding;
#[path = "integration/file_display.rs"]
mod file_display;
#[path = "integration/filesystem_tools.rs"]
mod filesystem_tools;
#[path = "integration/git_tools.rs"]
mod git_tools;
#[cfg(target_os = "linux")]
#[allow(dead_code)]
#[path = "support/helper.rs"]
mod helper;
#[cfg(target_os = "linux")]
#[path = "integration/helper_capture.rs"]
mod helper_capture;
#[cfg(target_os = "linux")]
#[path = "integration/lsp_binding.rs"]
mod lsp_binding;
#[cfg(target_os = "linux")]
#[path = "integration/lsp_leases.rs"]
mod lsp_leases;
#[path = "integration/lua_orchestration.rs"]
mod lua_orchestration;
#[cfg(target_os = "linux")]
#[path = "integration/lua_process.rs"]
mod lua_process;
#[path = "integration/mcp_dart_sdk.rs"]
mod mcp_dart_sdk;
#[path = "integration/mcp_host_http_lifecycle.rs"]
mod mcp_host_http_lifecycle;
#[cfg(target_os = "linux")]
#[path = "integration/mcp_remote_and_lifecycle.rs"]
mod mcp_remote_and_lifecycle;
#[allow(dead_code)]
#[path = "support/mcp_stdio.rs"]
mod mcp_stdio;
#[path = "integration/mcp_stdio_lifecycle.rs"]
mod mcp_stdio_lifecycle;
#[cfg(target_os = "linux")]
#[path = "integration/remote_directory.rs"]
mod remote_directory;
#[cfg(target_os = "linux")]
#[path = "integration/remote_resource.rs"]
mod remote_resource;
#[cfg(target_os = "linux")]
#[path = "support/remote.rs"]
mod remote_support;
#[path = "integration/search_host.rs"]
mod search_host;
#[cfg(target_os = "linux")]
#[path = "integration/ssh_lsp_real.rs"]
mod ssh_lsp_real;
#[path = "integration/standalone_tools.rs"]
mod standalone_tools;
#[path = "integration/task_control.rs"]
mod task_control;
#[path = "integration/typed_binding.rs"]
mod typed_binding;
