use crate::CancellationSignal;

/// Native Tokio signal streams register before initialization and remain alive through shutdown.
pub struct SignalListener {
    #[cfg(unix)]
    interrupt: tokio::signal::unix::Signal,
    #[cfg(unix)]
    terminate: tokio::signal::unix::Signal,
    #[cfg(windows)]
    interrupt: tokio::signal::windows::CtrlC,
}

impl SignalListener {
    pub fn new() -> std::io::Result<Self> {
        #[cfg(unix)]
        {
            use tokio::signal::unix::{SignalKind, signal};
            Ok(Self {
                interrupt: signal(SignalKind::interrupt())?,
                terminate: signal(SignalKind::terminate())?,
            })
        }
        #[cfg(windows)]
        {
            Ok(Self {
                interrupt: tokio::signal::windows::ctrl_c()?,
            })
        }
    }

    pub async fn recv(&mut self) -> CancellationSignal {
        #[cfg(unix)]
        {
            tokio::select! {
                _ = self.interrupt.recv() => CancellationSignal::Interrupt,
                _ = self.terminate.recv() => CancellationSignal::Terminate,
            }
        }
        #[cfg(windows)]
        {
            self.interrupt.recv().await;
            CancellationSignal::Interrupt
        }
    }
}
