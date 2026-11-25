use std::time::{Duration, Instant, SystemTime};

use reqwest::header::{HeaderMap, RETRY_AFTER};

/// Wall and monotonic readings taken at the same receive boundary.
#[derive(Debug, Clone, Copy)]
pub struct ErrorObservedAt {
    pub wall: SystemTime,
    pub monotonic: Instant,
}

impl ErrorObservedAt {
    pub fn now() -> Self {
        Self {
            wall: SystemTime::now(),
            monotonic: tokio::time::Instant::now().into_std(),
        }
    }
}

/// A minimum delay expressed by the upstream. An overflowing hint wins over
/// finite hints so that it can never be replaced by an earlier retry.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum RetryHint {
    #[default]
    Absent,
    Delay(Duration),
    Unrepresentable,
}

impl RetryHint {
    pub fn observed(self, at: ErrorObservedAt) -> ObservedRetry {
        match self {
            Self::Absent => ObservedRetry::Absent,
            Self::Delay(delay) => {
                let millis = delay.as_nanos().div_ceil(1_000_000);
                match (at.monotonic.checked_add(delay), u64::try_from(millis)) {
                    (Some(deadline), Ok(delay_ms)) => ObservedRetry::At {
                        deadline,
                        delay_ms,
                        wall: at.wall,
                    },
                    _ => ObservedRetry::Unrepresentable { wall: at.wall },
                }
            }
            Self::Unrepresentable => ObservedRetry::Unrepresentable { wall: at.wall },
        }
    }

    pub fn combine(self, other: Self) -> Self {
        match (self, other) {
            (Self::Unrepresentable, _) | (_, Self::Unrepresentable) => Self::Unrepresentable,
            (Self::Delay(left), Self::Delay(right)) => Self::Delay(left.max(right)),
            (hint, Self::Absent) | (Self::Absent, hint) => hint,
        }
    }

    pub fn from_millis(value: &str) -> Self {
        Self::from_unsigned(value, Duration::from_millis)
    }

    pub fn from_number_millis(value: &serde_json::Number) -> Self {
        if let Some(millis) = value.as_u64() {
            Self::Delay(Duration::from_millis(millis))
        } else if value.as_f64().is_some_and(|value| value >= u64::MAX as f64) {
            // serde_json can represent an overflowing integer as a floating-point number.
            Self::Unrepresentable
        } else {
            Self::Absent
        }
    }

    pub fn from_headers(headers: &HeaderMap, wall: SystemTime) -> Self {
        let standard = headers
            .get_all(RETRY_AFTER)
            .iter()
            .filter_map(|value| value.to_str().ok())
            .map(|value| {
                let value = value.trim();
                match Self::from_unsigned(value, Duration::from_secs) {
                    Self::Absent => httpdate::parse_http_date(value)
                        .ok()
                        .map(|date| Self::Delay(date.duration_since(wall).unwrap_or_default()))
                        .unwrap_or_default(),
                    hint => hint,
                }
            });
        let millis = headers
            .get_all("retry-after-ms")
            .iter()
            .chain(headers.get_all("retry_after_ms").iter())
            .filter_map(|value| value.to_str().ok())
            .map(|value| Self::from_millis(value.trim()));
        standard.chain(millis).fold(Self::Absent, Self::combine)
    }

    /// Parses the JSON encoding of a nonnegative protobuf Duration in RetryInfo.
    pub fn from_google_retry_delay(value: &str) -> Self {
        let Some(value) = value.strip_suffix('s') else {
            return Self::Absent;
        };
        let (seconds, nanos) = match value.split_once('.') {
            Some((seconds, fraction)) => {
                let len = fraction.len();
                if !(1..=9).contains(&len) || !fraction.bytes().all(|byte| byte.is_ascii_digit()) {
                    return Self::Absent;
                }
                let nanos = fraction
                    .parse::<u32>()
                    .expect("at most nine decimal digits")
                    * 10_u32.pow(9 - len as u32);
                (seconds, nanos)
            }
            None => (value, 0),
        };
        Self::from_unsigned(seconds, |seconds| Duration::new(seconds, nanos))
    }

    fn from_unsigned(value: &str, duration: impl FnOnce(u64) -> Duration) -> Self {
        if value.is_empty() || !value.bytes().all(|byte| byte.is_ascii_digit()) {
            return Self::Absent;
        }
        match value.parse::<u64>() {
            Ok(value) => Self::Delay(duration(value)),
            Err(_) => Self::Unrepresentable,
        }
    }
}

/// Retry constraints from different receive boundaries are combined as deadlines.
#[derive(Debug, Clone, Copy, Default, PartialEq, Eq)]
pub enum ObservedRetry {
    #[default]
    Absent,
    At {
        deadline: Instant,
        delay_ms: u64,
        wall: SystemTime,
    },
    Unrepresentable {
        wall: SystemTime,
    },
}

impl ObservedRetry {
    pub fn from_headers(headers: &HeaderMap, at: ErrorObservedAt) -> Self {
        RetryHint::from_headers(headers, at.wall).observed(at)
    }

    pub fn combine(self, other: Self) -> Self {
        match (self, other) {
            (hint @ Self::Unrepresentable { .. }, _) | (_, hint @ Self::Unrepresentable { .. }) => {
                hint
            }
            (left @ Self::At { deadline: a, .. }, right @ Self::At { deadline: b, .. }) => {
                if a >= b { left } else { right }
            }
            (hint, Self::Absent) | (Self::Absent, hint) => hint,
        }
    }
}
