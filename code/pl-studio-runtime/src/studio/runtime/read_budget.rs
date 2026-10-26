use std::io::{self, Write};
use std::sync::Mutex;

use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use serde::Serialize;

pub(super) const RESPONSE_BYTES: usize = 256 * 1024;
pub(super) const INLINE_BYTES: usize = 4096;

/// An access table contains only typed field locators, never another copy of the source strings.
pub(super) struct FieldTable<K>(Mutex<Vec<K>>);

impl<K> Default for FieldTable<K> {
    fn default() -> Self {
        Self(Mutex::new(Vec::new()))
    }
}

impl<K: Copy + Eq> FieldTable<K> {
    pub(super) fn read(
        &self,
        key: K,
        value: &str,
        inline_bytes: usize,
    ) -> Result<ReadText, StudioError> {
        if value.len() <= inline_bytes.min(INLINE_BYTES) {
            return Ok(ReadText::Inline {
                text: value.to_owned(),
            });
        }
        Ok(ReadText::Deferred {
            field_id: self.register(key)?,
            utf8_bytes: count(value.len())?,
        })
    }

    pub(super) fn register(&self, key: K) -> Result<u64, StudioError> {
        let mut fields = self
            .0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner);
        let index = match fields.iter().position(|field| *field == key) {
            Some(index) => index,
            None => {
                let index = fields.len();
                let _ = count(index)?.checked_add(1).ok_or_else(exhausted)?;
                fields.push(key);
                index
            }
        };
        count(index)?.checked_add(1).ok_or_else(exhausted)
    }

    pub(super) fn field(&self, field_id: u64) -> Result<K, StudioError> {
        let index = field_id
            .checked_sub(1)
            .and_then(|index| usize::try_from(index).ok())
            .ok_or_else(|| {
                StudioError::invalid_argument("Unknown field or list in this read scope")
            })?;
        self.0
            .lock()
            .unwrap_or_else(std::sync::PoisonError::into_inner)
            .get(index)
            .copied()
            .ok_or_else(|| {
                StudioError::invalid_argument("Unknown field or list in this read scope")
            })
    }
}

pub(super) fn count(value: usize) -> Result<u64, StudioError> {
    u64::try_from(value).map_err(|_| exhausted())
}

pub(super) fn bounded_header<T: Serialize>(
    mut build: impl FnMut(usize) -> Result<T, StudioError>,
) -> Result<T, StudioError> {
    let value = build(INLINE_BYTES)?;
    if json_bytes(&value)? <= RESPONSE_BYTES {
        return Ok(value);
    }
    // Small fields can still exceed the aggregate envelope once escaped. Deferring every text
    // preserves the complete fixed scalar schema; it does not truncate any source field.
    let deferred = build(0)?;
    require_budget(&deferred)?;
    Ok(deferred)
}

pub(super) fn text_chunk(
    field_id: u64,
    source: &str,
    offset: u64,
    max_bytes: u32,
) -> Result<TextChunk, StudioError> {
    if !(4..=RESPONSE_BYTES as u32).contains(&max_bytes) {
        return Err(StudioError::invalid_argument(
            "Text maxBytes must be in 4..=262144",
        ));
    }
    let start = usize::try_from(offset)
        .ok()
        .filter(|start| *start <= source.len() && source.is_char_boundary(*start))
        .ok_or_else(|| StudioError::invalid_argument("Text offset is not a UTF-8 byte boundary"))?;
    let mut end = start.saturating_add(max_bytes as usize).min(source.len());
    while !source.is_char_boundary(end) {
        end -= 1;
    }
    let chunk = |end: usize| -> Result<TextChunk, StudioError> {
        Ok(TextChunk {
            field_id,
            offset,
            text: source[start..end].to_owned(),
            next_offset: if end < source.len() {
                Some(count(end)?)
            } else {
                None
            },
        })
    };
    let candidate = chunk(end)?;
    if json_bytes(&candidate)? <= RESPONSE_BYTES {
        return Ok(candidate);
    }
    // Escaped JSON can be much larger than the UTF-8 content budget. Search only complete
    // character prefixes and account for the actual nextOffset/envelope on every candidate.
    let mut low = start;
    let mut high = end;
    while low < high {
        let mut middle = low + (high - low).div_ceil(2);
        while !source.is_char_boundary(middle) {
            middle -= 1;
        }
        if middle == low {
            middle = low
                + source[low..]
                    .chars()
                    .next()
                    .ok_or_else(|| protocol("Text prefix search could not advance"))?
                    .len_utf8();
        }
        if json_bytes(&chunk(middle)?)? <= RESPONSE_BYTES {
            low = middle;
        } else {
            high = middle - 1;
            while !source.is_char_boundary(high) {
                high -= 1;
            }
        }
    }
    if low == start && start < source.len() {
        return Err(exhausted());
    }
    let value = chunk(low)?;
    require_budget(&value)?;
    Ok(value)
}

pub(super) fn require_budget(value: &impl Serialize) -> Result<(), StudioError> {
    if json_bytes(value)? > RESPONSE_BYTES {
        return Err(exhausted());
    }
    Ok(())
}

pub(super) fn json_bytes(value: &impl Serialize) -> Result<usize, StudioError> {
    let mut counter = JsonBytes(0);
    serde_json::to_writer(&mut counter, value)
        .map_err(|_| protocol("Detail cannot be serialized by its typed schema"))?;
    Ok(counter.0)
}

struct JsonBytes(usize);

impl Write for JsonBytes {
    fn write(&mut self, bytes: &[u8]) -> io::Result<usize> {
        self.0 = self
            .0
            .checked_add(bytes.len())
            .ok_or_else(|| io::Error::other("JSON byte count overflow"))?;
        Ok(bytes.len())
    }

    fn flush(&mut self) -> io::Result<()> {
        Ok(())
    }
}

pub(super) fn protocol(message: &'static str) -> StudioError {
    StudioError::new(StudioErrorCode::Protocol, message, false)
}

fn exhausted() -> StudioError {
    StudioError::new(
        StudioErrorCode::Overloaded,
        "Detail exceeds its transport budget",
        false,
    )
}
