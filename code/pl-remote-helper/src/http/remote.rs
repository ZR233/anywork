use super::*;
use std::sync::Mutex;

struct ExchangeGuard {
    reset: stream::Reset,
    cancel: CancellationToken,
    armed: bool,
}
impl Drop for ExchangeGuard {
    fn drop(&mut self) {
        if self.armed {
            self.cancel.cancel();
            self.reset
                .lock()
                .unwrap_or_else(std::sync::PoisonError::into_inner)
                .send_reset(h2::Reason::CANCEL);
        }
    }
}

impl crate::remote::RemoteConnection {
    pub async fn http(
        &self,
        executor: Executor,
        exchange: Exchange,
        mut input: HttpInput,
    ) -> Result<HttpResponse, ExecutionError> {
        let descriptor = stream::encode_descriptor(&exchange)
            .map_err(|error| ExecutionError::io("HTTP descriptor", error))?;
        let permit = self.permit(1, false).await?;
        let (response, output) = self.open("POST", "/http", false).await?;
        let output = Arc::new(Mutex::new(output));
        let cancel = CancellationToken::new();
        let mut guard = ExchangeGuard {
            reset: output.clone(),
            cancel: cancel.clone(),
            armed: true,
        };
        stream::send_shared(&output, descriptor.into(), false, &self.closing)
            .await
            .map_err(|error| ExecutionError::io("HTTP descriptor", error))?;
        let stop = cancel.clone();
        let closing = self.closing.clone();
        let sender = output.clone();
        let held = permit.clone();
        let (notify, finished) = tokio::sync::oneshot::channel::<stream::Trailers>();
        self.tasks.spawn(async move {
            let _permit = held;
            let upload = async {
                let mut bytes = vec![0; stream::WINDOW as usize];
                loop {
                    let count = input.read(&mut bytes).await?;
                    if count == 0 { return stream::send_shared(&sender, Bytes::new(), true, &closing).await; }
                    stream::send_shared(&sender, Bytes::copy_from_slice(&bytes[..count]), false, &closing).await?;
                }
            };
            let response_eos = async {
                if let Ok(mut done) = finished.await { let _ = done.wait_for(Option::is_some).await; }
            };
            tokio::select! {
                biased;
                _ = stop.cancelled() => {},
                _ = closing.cancelled() => {},
                _ = response_eos => {
                    // A legitimate early response has ended. Stop the source and half-close;
                    // a peer NO_ERROR here is compatible with that complete response.
                    let _ = stream::send_shared(&sender, Bytes::new(), true, &closing).await;
                },
                result = upload => if let Err(error) = result {
                    let no_error = error.get_ref().and_then(|source| source.downcast_ref::<h2::Error>()).is_some_and(|error| error.reason() == Some(h2::Reason::NO_ERROR));
                    if !no_error { sender.lock().unwrap_or_else(std::sync::PoisonError::into_inner).send_reset(h2::Reason::CANCEL); }
                },
            }
            // input and sender are destroyed before the last admission owner is released.
            drop(input); drop(sender);
        });
        let response = tokio::select! {
            response = response => response.map_err(|error| ExecutionError::io("HTTP response", io::Error::other(error)))?,
            _ = self.closing.cancelled() => return Err(ExecutionError::Disconnected("HTTP connection closed".into())),
        };
        if !response.status().is_success() {
            let bytes = stream::collect(response.into_body(), crate::wire::RESULT_LIMIT)
                .await
                .map_err(|error| ExecutionError::io("HTTP error response", error))?;
            return Err(serde_json::from_slice::<crate::wire::Failure>(&bytes)
                .map_err(|error| ExecutionError::Protocol(error.to_string()))?
                .into());
        }
        let (mut reader, done) = stream::receive(
            response.into_body(),
            output.into(),
            &self.tasks,
            self.closing.clone(),
            Some(permit),
        );
        let _ = notify.send(done);
        let head = stream::read_descriptor(&mut reader)
            .await
            .map_err(|error| ExecutionError::io("HTTP response descriptor", error))?;
        guard.armed = false;
        Ok(HttpResponse {
            head,
            body: HttpBody {
                reader: Box::pin(reader),
                cancel,
                _executor: executor,
            },
        })
    }
}

pub(crate) async fn serve(
    input: h2::RecvStream,
    mut response: h2::server::SendResponse<Bytes>,
    executor: Executor,
    tasks: tokio_util::task::TaskTracker,
    closing: CancellationToken,
) {
    let (mut reader, owner) = stream::receive_half(input, &tasks, closing.clone(), None);
    let prepare = async {
        let exchange: Exchange = stream::read_descriptor(&mut reader)
            .await
            .map_err(|error| ExecutionError::io("HTTP request descriptor", error))?;
        executor
            .http()
            .redirect(exchange.redirect)
            .execute(exchange.request, Box::pin(reader))
            .await
    };
    let result = tokio::select! {
        result = prepare => result,
        _ = closing.cancelled() => { owner.abandon().await; return; },
        _ = futures::future::poll_fn(|cx| response.poll_reset(cx)) => { owner.abandon().await; return; },
    };
    let mut response_body = match result {
        Ok(result) => result,
        Err(error) => {
            owner.abandon().await;
            crate::stdio_server::reply(
                response,
                ::http::StatusCode::BAD_REQUEST,
                serde_json::to_vec(&crate::wire::Failure::from(&error))
                    .expect("failure serializes"),
                closing,
            )
            .await;
            return;
        }
    };
    let Ok(mut output) = response.send_response(::http::Response::new(()), false) else {
        owner.abandon().await;
        return;
    };
    let operation: io::Result<()> = async {
        let descriptor = stream::encode_descriptor(&response_body.head)?;
        stream::send(&mut output, descriptor.into(), false, &closing).await?;
        let mut bytes = vec![0; stream::WINDOW as usize];
        loop {
            let count = tokio::select! {
                result = response_body.body.read(&mut bytes) => result?,
                _ = closing.cancelled() => return Err(io::ErrorKind::Interrupted.into()),
                _ = futures::future::poll_fn(|cx| output.poll_reset(cx)) => return Err(io::ErrorKind::Interrupted.into()),
            };
            if count == 0 { return Ok(()); }
            stream::send(&mut output, Bytes::copy_from_slice(&bytes[..count]), false, &closing).await?;
        }
    }.await;
    drop(response_body);
    // Only the exchange owner abandons the input half. It joins the receive pump
    // and returns polled-but-unconsumed credit without cancelling the response.
    owner.abandon().await;
    if operation.is_ok() {
        let _ = output.send_data(Bytes::new(), true);
    } else {
        output.send_reset(h2::Reason::CANCEL);
    }
}
