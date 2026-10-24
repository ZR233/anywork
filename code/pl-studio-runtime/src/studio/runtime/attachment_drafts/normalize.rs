//! Typed metadata inspection of original bytes; no image/video transformation or filename proof.
use anyhow::{Context, Result};
use image::ImageDecoder;
use pl_protocol::studio::{ATTACHMENT_MAX_FILE_BYTES, StudioAttachmentModality};
use std::io::{BufReader, Seek, SeekFrom};
use tokio_util::sync::CancellationToken;

mod reader;
use reader::ProbeReader;

#[derive(Debug, thiserror::Error)]
#[error("attachment inspection cancelled")]
pub(super) struct InspectionCancelled;

pub(super) struct NormalizedSource {
    pub(super) modality: StudioAttachmentModality,
    pub(super) media_type: String,
    pub(super) bytes: Vec<u8>,
    pub(super) width: Option<u32>,
    pub(super) height: Option<u32>,
}

struct Metadata {
    modality: StudioAttachmentModality,
    media_type: &'static str,
    width: Option<u32>,
    height: Option<u32>,
}

pub(super) fn normalize_loaded_source(
    bytes: Vec<u8>,
    cancellation: CancellationToken,
) -> Result<NormalizedSource> {
    anyhow::ensure!(
        bytes.len() as u64 <= ATTACHMENT_MAX_FILE_BYTES,
        "attachment exceeds 50 MiB"
    );
    let mut reader = ProbeReader::new(&bytes, cancellation);
    let inspected = inspect(&bytes, &mut reader);
    // Library error wrappers must not turn cooperative cancellation or exhausted IO
    // budgets into a successful generic-file classification.
    reader.check()?;
    let metadata = inspected?;
    Ok(NormalizedSource {
        modality: metadata.modality,
        media_type: metadata.media_type.into(),
        bytes,
        width: metadata.width,
        height: metadata.height,
    })
}

fn inspect(bytes: &[u8], reader: &mut ProbeReader<'_>) -> Result<Metadata> {
    if let Ok(format) = image::guess_format(bytes) {
        return match inspect_image(reader, format) {
            Ok(Some((width, height))) => Ok(Metadata {
                modality: StudioAttachmentModality::Image,
                media_type: format.to_mime_type(),
                width: Some(width),
                height: Some(height),
            }),
            Ok(None) => Ok(file_metadata(bytes)),
            Err(image::ImageError::Decoding(_) | image::ImageError::Unsupported(_)) => {
                Ok(file_metadata(bytes))
            }
            Err(image::ImageError::IoError(error))
                if matches!(
                    error.kind(),
                    std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::InvalidData
                ) =>
            {
                Ok(file_metadata(bytes))
            }
            Err(error) => Err(error).context("image metadata inspection failed"),
        };
    }
    match mp4parse::read_mp4(reader) {
        Ok(context) => {
            if context
                .tracks
                .iter()
                .any(|track| track.track_type == mp4parse::TrackType::Video)
            {
                // infer selects only the MIME subtype, after the parser established a
                // video track. Neither a filename nor a magic match authorizes video input.
                let media_type = if infer::get(bytes)
                    .is_some_and(|kind| kind.mime_type() == "video/quicktime")
                {
                    "video/quicktime"
                } else {
                    "video/mp4"
                };
                return Ok(Metadata {
                    modality: StudioAttachmentModality::Video,
                    media_type,
                    width: None,
                    height: None,
                });
            }
            return Ok(file_metadata(bytes));
        }
        Err(
            mp4parse::Error::InvalidData(_)
            | mp4parse::Error::Unsupported(_)
            | mp4parse::Error::UnexpectedEOF
            | mp4parse::Error::MoovMissing,
        ) => {}
        Err(error) => return Err(error).context("MP4 metadata inspection failed"),
    }
    reader
        .seek(SeekFrom::Start(0))
        .context("rewind media snapshot")?;
    let matroska = matroska_demuxer::MatroskaFile::open(reader).map(|file| {
        if !file
            .tracks()
            .iter()
            .any(|track| track.track_type() == matroska_demuxer::TrackType::Video)
        {
            return None;
        }
        match file.ebml_header().doc_type().trim_end_matches('\0') {
            "webm" => Some("video/webm"),
            "matroska" => Some("video/x-matroska"),
            _ => None,
        }
    });
    use matroska_demuxer::DemuxError;
    let media_type = match matroska {
        Ok(media_type) => media_type,
        Err(DemuxError::IoError(error))
            if matches!(
                error.kind(),
                std::io::ErrorKind::UnexpectedEof | std::io::ErrorKind::InvalidData
            ) =>
        {
            None
        }
        Err(DemuxError::IoError(error)) => {
            return Err(error).context("Matroska metadata inspection IO failed");
        }
        Err(
            DemuxError::FromUtf8Error(_)
            | DemuxError::TryFromIntError(_)
            | DemuxError::InvalidEbmlElementId
            | DemuxError::InvalidEbmlDataSize
            | DemuxError::InvalidEbmlHeader(_)
            | DemuxError::WrongFloatSize(_)
            | DemuxError::WrongIntegerSize(_)
            | DemuxError::WrongDateSize(_)
            | DemuxError::UnsupportedDocType(_)
            | DemuxError::UnsupportedDocTypeReadVersion(_)
            | DemuxError::UnexpectedElement(_)
            | DemuxError::UnexpectedDataType
            | DemuxError::ElementNotFound(_)
            | DemuxError::CantFindCluster
            | DemuxError::NonZeroValueIsZero(_)
            | DemuxError::PositiveValueIsNotPositive
            | DemuxError::FrameAlreadyHasDuration(_)
            | DemuxError::ElementSizeExceedsStream { .. }
            | DemuxError::InvalidBlockSize,
        ) => None,
    };
    Ok(match media_type {
        Some(media_type) => Metadata {
            modality: StudioAttachmentModality::Video,
            media_type,
            width: None,
            height: None,
        },
        None => file_metadata(bytes),
    })
}

fn inspect_image(
    reader: &mut ProbeReader<'_>,
    format: image::ImageFormat,
) -> image::ImageResult<Option<(u32, u32)>> {
    use image::error::LimitErrorKind;

    let mut limits = image::Limits::default();
    // Metadata must remain readable before a configured geometry rejection. Its own
    // allocation/decoder errors still propagate; they are not proof of a policy limit.
    let mut metadata_limits = limits.clone();
    metadata_limits.max_image_width = None;
    metadata_limits.max_image_height = None;
    let mut image_reader = image::ImageReader::with_format(BufReader::new(reader), format);
    image_reader.limits(metadata_limits);
    let mut decoder = image_reader.into_decoder()?;
    let (width, height) = decoder.dimensions();

    // Only these allocation-free Limits checks prove a configured restriction. In image
    // 0.25, InsufficientMemory also represents TryReserveError; never downgrade that kind
    // when returned by decoder construction, set_limits or the actual pixel allocation.
    if let Err(error) = limits.check_dimensions(width, height) {
        return match error {
            image::ImageError::Limits(error)
                if matches!(error.kind(), LimitErrorKind::DimensionError) =>
            {
                Ok(None)
            }
            error => Err(error),
        };
    }
    if let Err(error) = limits.reserve(decoder.total_bytes()) {
        return match error {
            image::ImageError::Limits(error)
                if matches!(error.kind(), LimitErrorKind::InsufficientMemory) =>
            {
                Ok(None)
            }
            error => Err(error),
        };
    }
    decoder.set_limits(limits)?;
    let decoded = image::DynamicImage::from_decoder(decoder)?;
    Ok(Some((decoded.width(), decoded.height())))
}

fn file_metadata(bytes: &[u8]) -> Metadata {
    let media_type = if bytes.starts_with(b"%PDF-") {
        "application/pdf"
    } else if bytes.starts_with(b"PK\x03\x04") {
        "application/zip"
    } else if std::str::from_utf8(bytes).is_ok_and(|text| {
        text.chars()
            .all(|character| !character.is_control() || matches!(character, '\n' | '\r' | '\t'))
    }) {
        "text/plain"
    } else {
        "application/octet-stream"
    };
    Metadata {
        modality: StudioAttachmentModality::File,
        media_type,
        width: None,
        height: None,
    }
}

pub(super) fn sanitize_filename(filename: &str) -> String {
    filename
        .chars()
        .take(120)
        .map(|character| {
            if character.is_alphanumeric() || matches!(character, '.' | '-' | '_' | ' ') {
                character
            } else {
                '_'
            }
        })
        .collect::<String>()
        .trim()
        .trim_matches('.')
        .to_string()
}
