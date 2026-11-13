use pl_studio_mcp::{
    HostError, HostMcpService, IPC_CAPABILITY_ENV, IPC_ENDPOINT_ENV, STDIO_ARG, ipc::IpcClient,
};
use rmcp::ServiceExt;
use tokio_util::sync::CancellationToken;

fn main() {
    let args: Vec<_> = std::env::args_os().skip(1).collect();
    if args.len() != 1 || args[0] != STDIO_ARG {
        eprintln!("expected --stdio");
        std::process::exit(2);
    }
    let runtime = match tokio::runtime::Builder::new_multi_thread()
        .enable_all()
        .build()
    {
        Ok(runtime) => runtime,
        Err(_) => {
            eprintln!("host service runtime failed");
            std::process::exit(1);
        }
    };
    let result = runtime.block_on(run());
    let code = match result {
        Ok(()) => 0,
        Err(error) => {
            eprintln!("{error}");
            1
        }
    };
    // All MCP/IPC async owners have been closed and joined by run(). On macOS,
    // Windows, or non-FIFO stdin, official Tokio stdin uses an uncancellable
    // blocking read. Normal process exit ends ONLY that input thread; do not
    // wait forever in Runtime::drop or treat a dropped business task as joined.
    std::process::exit(code);
}

async fn run() -> Result<(), HostError> {
    let endpoint = std::env::var(IPC_ENDPOINT_ENV).map_err(|_| HostError::InvalidRequest)?;
    let capability = std::env::var(IPC_CAPABILITY_ENV).map_err(|_| HostError::Unauthorized)?;
    let client = IpcClient::connect(endpoint, capability).await?;
    let cancellation = CancellationToken::new();
    let result = async {
        let initialize = HostMcpService::new(client.clone())
            .serve_with_ct(rmcp::transport::stdio_pipes(), cancellation.clone());
        tokio::pin!(initialize);
        let service = tokio::select! {
            result = &mut initialize => result.map_err(|_| HostError::Transport)?,
            _ = client.closed() => {
                cancellation.cancel();
                // Finish half-initialized official transport before collecting IPC.
                let _ = initialize.await;
                return Err(HostError::Transport);
            }
        };
        let waiting = service.waiting();
        tokio::pin!(waiting);
        tokio::select! {
            result = &mut waiting => result.map(|_| ()).map_err(|_| HostError::Transport),
            _ = client.closed() => {
                cancellation.cancel();
                let _ = waiting.await.map_err(|_| HostError::Transport)?;
                Err(HostError::Transport)
            }
        }
    }
    .await;
    cancellation.cancel();
    let closed = client.close().await;
    result.and(closed)
}
