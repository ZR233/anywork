use std::sync::Arc;

use tokio::sync::watch;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CaptureSpec {
    pub stdout_path: String,
    pub stderr_path: String,
    pub max_bytes: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum CaptureState {
    Complete,
    LimitExceeded,
    IoFailed,
    Incomplete,
}

#[derive(Debug, Clone)]
pub struct CapturedStream {
    pub state: CaptureState,
    pub confirmed_bytes: Option<u64>,
    pub error: Option<Arc<std::io::Error>>,
}

#[derive(Debug, Clone)]
pub struct CaptureResult {
    pub stdout: CapturedStream,
    pub stderr: CapturedStream,
}

pub(crate) type CaptureCompletion = watch::Receiver<Option<CapturedStream>>;

pub(crate) async fn completion(receiver: &mut CaptureCompletion) -> CapturedStream {
    loop {
        if let Some(result) = receiver.borrow().clone() {
            return result;
        }
        if receiver.changed().await.is_err() {
            return CapturedStream {
                state: CaptureState::Incomplete,
                confirmed_bytes: None,
                error: None,
            };
        }
    }
}

/// Publication follows the public reader's EOF, not the pump receiving trailers.
/// Abandoning buffered output must settle capture as incomplete immediately.
pub(crate) fn observe(
    reader: std::pin::Pin<Box<dyn tokio::io::AsyncRead + Send>>,
    outcome: impl Fn() -> CapturedStream + Send + 'static,
) -> (
    std::pin::Pin<Box<dyn tokio::io::AsyncRead + Send>>,
    CaptureCompletion,
) {
    let (completion, observed) = watch::channel(None);
    (
        Box::pin(CaptureReader {
            reader,
            outcome: Box::new(outcome),
            completion: Some(completion),
        }),
        observed,
    )
}

struct CaptureReader {
    reader: std::pin::Pin<Box<dyn tokio::io::AsyncRead + Send>>,
    outcome: Box<dyn Fn() -> CapturedStream + Send>,
    completion: Option<watch::Sender<Option<CapturedStream>>>,
}
impl Drop for CaptureReader {
    fn drop(&mut self) {
        if let Some(completion) = self.completion.take() {
            completion.send_replace(Some(CapturedStream {
                state: CaptureState::Incomplete,
                confirmed_bytes: None,
                error: None,
            }));
        }
    }
}
impl tokio::io::AsyncRead for CaptureReader {
    fn poll_read(
        mut self: std::pin::Pin<&mut Self>,
        cx: &mut std::task::Context<'_>,
        buffer: &mut tokio::io::ReadBuf<'_>,
    ) -> std::task::Poll<std::io::Result<()>> {
        let before = buffer.filled().len();
        let capacity = buffer.remaining();
        let result = self.reader.as_mut().poll_read(cx, buffer);
        if matches!(result, std::task::Poll::Ready(Err(_)))
            || (matches!(result, std::task::Poll::Ready(Ok(())))
                && capacity != 0
                && before == buffer.filled().len())
        {
            let outcome = (self.outcome)();
            if let Some(completion) = self.completion.take() {
                completion.send_replace(Some(outcome));
            }
        }
        result
    }
}
