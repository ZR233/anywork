use std::{error::Error, fmt::Write, io::ErrorKind};

use pl_protocol::{
    ProviderFailure, ProviderFailureKind as Kind, ProviderFailureStage, PureError, RetryDisposition,
};

use super::{redact_secret_like_values, transport_failure};

pub fn reqwest_error_to_pure(error: reqwest::Error) -> PureError {
    let error = error.without_url();
    let detail = reqwest_error_detail(&error);
    let mut failure =
        if error.is_timeout() || error.is_connect() || response_start_connection_closed(&error) {
            transport_failure(ProviderFailureStage::Request, detail)
        } else {
            let kind = if error.is_builder() || error.is_redirect() {
                Kind::InvalidRequest
            } else if error.is_decode() || error.is_body() {
                // This boundary also handles Response::json(). Raw body reads use
                // reqwest_body_error_to_pure before any model decoding.
                Kind::Protocol
            } else {
                Kind::Unknown
            };
            let mut failure = ProviderFailure::new(kind, detail, RetryDisposition::Permanent);
            failure.context.stage = ProviderFailureStage::Request;
            failure
        };
    failure.http_status = error.status().map(|status| status.as_u16());
    failure.with_source(error).into()
}

pub fn reqwest_body_error_to_pure(error: reqwest::Error) -> PureError {
    // At bytes_stream(), Decode describes HTTP body framing or decoding.
    let error = error.without_url();
    let detail = format!(
        "response body read failed: {}",
        reqwest_error_detail(&error)
    );
    let mut failure = transport_failure(ProviderFailureStage::Stream, detail);
    failure.http_status = error.status().map(|status| status.as_u16());
    failure.with_source(error).into()
}

fn reqwest_error_detail(error: &reqwest::Error) -> String {
    let mut detail = redact_secret_like_values(&error.to_string());
    if error.is_timeout() {
        detail.push_str("; timeout=true");
    }
    let mut source = error.source();
    for _ in 0..8 {
        let Some(cause) = source else { break };
        // Hyper's Display is a fixed category. Arbitrary sources can contain
        // request URLs, credentials or provider content.
        if let Some(error) = cause.downcast_ref::<hyper::Error>() {
            let _ = write!(detail, "; hyper={error}");
        } else if let Some(error) = cause.downcast_ref::<std::io::Error>() {
            let _ = write!(detail, "; io={:?}", error.kind());
            if let Some(code) = error.raw_os_error() {
                let _ = write!(detail, "; os_code={code}");
            }
        }
        source = cause.source();
    }
    detail
}

fn response_start_connection_closed(error: &reqwest::Error) -> bool {
    if error.is_builder() || error.is_redirect() || error.is_status() {
        return false;
    }
    let mut source = error.source();
    for _ in 0..8 {
        let Some(cause) = source else { break };
        if cause.downcast_ref::<std::io::Error>().is_some_and(|error| {
            matches!(
                error.kind(),
                ErrorKind::ConnectionAborted
                    | ErrorKind::ConnectionReset
                    | ErrorKind::BrokenPipe
                    | ErrorKind::UnexpectedEof
                    | ErrorKind::TimedOut
            )
        }) || cause
            .downcast_ref::<hyper::Error>()
            .is_some_and(|error| error.is_incomplete_message() || error.is_closed())
        {
            return true;
        }
        source = cause.source();
    }
    false
}
