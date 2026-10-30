//! Typed, frozen TOML formats. The resource owner retains all IO and commit state.
mod main;
mod profile;
mod wire;

pub(super) use main::{MainV29, load_current_main, load_main};
pub(super) use profile::load_current as load_current_profile;
pub(super) use profile::{ProfileV1, load_profile};

use anyhow::{Result, ensure};
use serde::{Deserialize, Serialize};

pub(super) const VERSION_KEY: &str = "schema_version";

/// An alias pair is resolved during DTO decoding, before an infallible migration runs.
fn identity<T: PartialEq>(old: Option<T>, new: Option<T>, field: &str) -> Result<T> {
    match (old, new) {
        (Some(old), Some(new)) => {
            ensure!(old == new, "conflicting historical {field} identities");
            Ok(new)
        }
        (Some(value), None) | (None, Some(value)) => Ok(value),
        (None, None) => anyhow::bail!("missing {field} identity"),
    }
}

fn optional_identity<T: PartialEq>(
    old: Option<T>,
    new: Option<T>,
    field: &str,
) -> Result<Option<T>> {
    if old.is_none() && new.is_none() {
        return Ok(None);
    }
    identity(old, new, field).map(Some)
}

/// Only the final, current wire shape crosses into a mutable domain type.
fn into_current<W: Serialize, D: for<'de> Deserialize<'de>>(wire: &W) -> Result<D> {
    toml::Value::try_from(wire)?.try_into().map_err(Into::into)
}
