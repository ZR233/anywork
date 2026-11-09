//! Selects an already authorized archived image; never reads product history or new bytes.
use pl_agent_tool::typed::TypedTool;
use std::marker::PhantomData;

pub const NAME: &str = "show_image";
pub const DESCRIPTION: &str = "Display one image this thread already archived as a timeline image card. Pass an optional short caption; the image is chosen from archived thread attachments. This does not read workspace files, fetch remote URLs or add new image bytes.";
pub const CARD_NOTE: &str = "An image card was added to the timeline.";

#[derive(Debug, serde::Deserialize, schemars::JsonSchema)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct Input {
    /// Optional card text, trimmed; an empty text or omission shows no caption (<= 240 chars).
    pub caption: Option<String>,
    /// Optional identity of one archived image; omitted displays the newest archived image.
    pub image_id: Option<String>,
}

/// Host-authorized candidates must be ordered newest first.
pub struct ArchivedImage<R> {
    pub id: String,
    pub image: R,
}

pub struct Output<R> {
    pub image: R,
    pub caption: Option<String>,
}

#[derive(Debug, thiserror::Error)]
pub enum ShowImageError {
    #[error("image card caption exceeds 240 characters")]
    CaptionTooLong,
    #[error("archived image id not found in this thread")]
    NotFound,
    #[error("no archived image in this thread")]
    NoImage,
}

pub struct ShowImage<R>(PhantomData<fn() -> R>);
impl<R> Default for ShowImage<R> {
    fn default() -> Self {
        Self(PhantomData)
    }
}

impl<R: Send + 'static> TypedTool for ShowImage<R> {
    const NAME: &'static str = NAME;
    const DESCRIPTION: &'static str = DESCRIPTION;
    type Args = Input;
    type Context = Vec<ArchivedImage<R>>;
    type Output = Output<R>;
    type Error = ShowImageError;

    async fn execute(
        &self,
        input: Input,
        candidates: Self::Context,
    ) -> Result<Self::Output, Self::Error> {
        let caption = input
            .caption
            .as_deref()
            .map(str::trim)
            .filter(|caption| !caption.is_empty())
            .map(str::to_owned);
        if caption
            .as_ref()
            .is_some_and(|caption| caption.chars().count() > 240)
        {
            return Err(ShowImageError::CaptionTooLong);
        }
        let image = candidates
            .into_iter()
            .find(|candidate| input.image_id.as_ref().is_none_or(|id| &candidate.id == id))
            .ok_or(if input.image_id.is_some() {
                ShowImageError::NotFound
            } else {
                ShowImageError::NoImage
            })?;
        Ok(Output {
            image: image.image,
            caption,
        })
    }
}
