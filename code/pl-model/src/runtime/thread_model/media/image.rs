//! Request-only image projection. Metadata-only native pass-through never decodes the original.
use super::{NativeMedia, failure, invalid, native_metadata};
use crate::{
    completion::AttachmentModality,
    model::{ModelInfo, ModelModality},
};
use image::ImageDecoder;
use pl_core::model::{ModelError, ModelFailureKind};
use std::{io::BufReader, sync::Arc};
use tokio_util::sync::CancellationToken;

mod io;
mod owner;
use io::{ImageCancellation, ImageReader, ImageWriter};
pub use owner::ModelPreparationOwner;

const MAX_SOURCE_EDGE: u32 = 16_384;
const MAX_SOURCE_PIXELS: u64 = 67_108_864;
const MAX_DECODED_BYTES: u64 = 256 * 1024 * 1024;

#[derive(Clone, Copy)]
enum Projection {
    Strict,
    UserFile,
}

pub(super) async fn validate(
    owner: &ModelPreparationOwner,
    model: &ModelInfo,
    media_type: &str,
    bytes: Arc<[u8]>,
    cancellation: CancellationToken,
) -> Result<(), ModelError> {
    owner
        .run(
            model.clone(),
            media_type.to_owned(),
            bytes,
            Projection::Strict,
            cancellation,
        )
        .await
        .map(|_| ())
}

pub(super) async fn derive(
    owner: &ModelPreparationOwner,
    model: &ModelInfo,
    media_type: &str,
    bytes: Arc<[u8]>,
    cancellation: CancellationToken,
) -> Result<Option<NativeMedia>, ModelError> {
    owner
        .run(
            model.clone(),
            media_type.to_owned(),
            bytes,
            Projection::UserFile,
            cancellation,
        )
        .await
}

fn cancelled() -> ModelError {
    failure(
        ModelFailureKind::Cancelled,
        std::io::Error::other("image preparation cancelled"),
    )
}

#[derive(Debug, thiserror::Error)]
#[error("image derivation source exceeds budget ({width}x{height}, {bytes} decoded bytes)")]
struct ImageBudgetExceeded {
    width: u32,
    height: u32,
    bytes: u64,
}

fn project(
    model: &ModelInfo,
    media_type: &str,
    bytes: Arc<[u8]>,
    projection: Projection,
    cancellation: &ImageCancellation,
) -> Result<Option<NativeMedia>, ModelError> {
    cancellation.check()?;
    let limits = &model
        .capabilities
        .input_capability(ModelModality::Image)
        .ok_or_else(|| invalid("image capability is missing"))?
        .limits;
    let format = match image::guess_format(&bytes) {
        Ok(format) if format.to_mime_type() == media_type => format,
        _ => return unsupported(projection, "image bytes do not match their media type"),
    };
    let mut reader = image::ImageReader::with_format(
        BufReader::new(ImageReader::new(bytes.clone(), cancellation.clone())),
        format,
    );
    // Metadata construction uses the library's allocation limit too, but source geometry
    // limits apply only when decoding a derivative, not to metadata-only raw pass-through.
    let mut metadata_limits = image::Limits::default();
    metadata_limits.max_alloc = Some(MAX_DECODED_BYTES);
    reader.limits(metadata_limits);
    let mut decoder = match reader.into_decoder() {
        Ok(decoder) => decoder,
        Err(error) => return decode_failure(error, projection),
    };
    let (width, height) = decoder.dimensions();
    cancellation.check()?;
    if width == 0 || height == 0 {
        return unsupported(projection, "image has zero dimensions");
    }
    let native_dimensions = limits.max_width.is_none_or(|limit| width <= limit)
        && limits.max_height.is_none_or(|limit| height <= limit);
    if native_dimensions
        && native_metadata(
            model,
            AttachmentModality::Image,
            media_type,
            bytes.len() as u64,
        )
    {
        return Ok(Some(NativeMedia {
            media_type: media_type.into(),
            bytes,
        }));
    }
    if matches!(projection, Projection::Strict) {
        return Err(invalid("image dimensions exceed the model limits"));
    }
    let pixels = u64::from(width).checked_mul(u64::from(height));
    let expected = pixels
        .and_then(|pixels| pixels.checked_mul(u64::from(decoder.color_type().bytes_per_pixel())));
    let decoded_bytes = decoder.total_bytes();
    if width > MAX_SOURCE_EDGE
        || height > MAX_SOURCE_EDGE
        || pixels.is_none_or(|pixels| pixels > MAX_SOURCE_PIXELS)
        || expected.is_none_or(|bytes| bytes > MAX_DECODED_BYTES)
        || decoded_bytes > MAX_DECODED_BYTES
    {
        return Err(failure(
            ModelFailureKind::Unavailable,
            ImageBudgetExceeded {
                width,
                height,
                bytes: decoded_bytes,
            },
        ));
    }
    let mut decode_limits = image::Limits::default();
    decode_limits.max_image_width = Some(MAX_SOURCE_EDGE);
    decode_limits.max_image_height = Some(MAX_SOURCE_EDGE);
    decode_limits.max_alloc = Some(MAX_DECODED_BYTES);
    decoder.set_limits(decode_limits).map_err(unavailable)?;
    cancellation.check()?;
    let decoded = match image::DynamicImage::from_decoder(decoder) {
        Ok(decoded) => decoded,
        Err(error) => return decode_failure(error, projection),
    };
    cancellation.check()?;
    let width = limits.max_width.unwrap_or(width).min(width);
    let height = limits.max_height.unwrap_or(height).min(height);
    if width == 0 || height == 0 {
        return Ok(None);
    }
    let byte_limit = limits.max_bytes.unwrap_or(32 * 1024 * 1024);
    for divisor in [1, 2, 4, 8, 16] {
        cancellation.check()?;
        let candidate = decoded.thumbnail((width / divisor).max(1), (height / divisor).max(1));
        cancellation.check()?;
        if limits.media_types.is_empty()
            || limits.media_types.iter().any(|media| media == "image/png")
        {
            let mut output = ImageWriter::new(cancellation.clone(), byte_limit);
            let result = candidate.write_to(&mut output, image::ImageFormat::Png);
            cancellation.check()?;
            if !output.limit_exceeded {
                result.map_err(unavailable)?;
                let bytes = output.into_bytes();
                if native_metadata(
                    model,
                    AttachmentModality::Image,
                    "image/png",
                    bytes.len() as u64,
                ) {
                    return Ok(Some(NativeMedia {
                        media_type: "image/png".into(),
                        bytes: bytes.into(),
                    }));
                }
            }
        }
        if limits.media_types.is_empty()
            || limits.media_types.iter().any(|media| media == "image/jpeg")
        {
            cancellation.check()?;
            let rgb = candidate.to_rgb8();
            cancellation.check()?;
            for quality in [85, 75, 65, 55, 45, 35] {
                cancellation.check()?;
                let mut output = ImageWriter::new(cancellation.clone(), byte_limit);
                let result =
                    image::codecs::jpeg::JpegEncoder::new_with_quality(&mut output, quality)
                        .encode(
                            rgb.as_raw(),
                            rgb.width(),
                            rgb.height(),
                            image::ExtendedColorType::Rgb8,
                        );
                cancellation.check()?;
                if !output.limit_exceeded {
                    result.map_err(unavailable)?;
                    let bytes = output.into_bytes();
                    if native_metadata(
                        model,
                        AttachmentModality::Image,
                        "image/jpeg",
                        bytes.len() as u64,
                    ) {
                        return Ok(Some(NativeMedia {
                            media_type: "image/jpeg".into(),
                            bytes: bytes.into(),
                        }));
                    }
                }
            }
        }
    }
    Ok(None)
}

fn unsupported(
    projection: Projection,
    message: &'static str,
) -> Result<Option<NativeMedia>, ModelError> {
    match projection {
        Projection::Strict => Err(invalid(message)),
        Projection::UserFile => Ok(None),
    }
}
fn unavailable(error: image::ImageError) -> ModelError {
    failure(ModelFailureKind::Unavailable, error)
}
fn decode_failure(
    error: image::ImageError,
    projection: Projection,
) -> Result<Option<NativeMedia>, ModelError> {
    match error {
        image::ImageError::Decoding(_) | image::ImageError::Unsupported(_) => {
            unsupported(projection, "image format is unsupported or invalid")
        }
        image::ImageError::IoError(ref io)
            if matches!(
                io.kind(),
                std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::InvalidData
            ) =>
        {
            unsupported(projection, "image snapshot is truncated or invalid")
        }
        error => Err(unavailable(error)),
    }
}
