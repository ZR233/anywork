//! Independent consumers exercise actual tools; the fixture only supplies bytes and storage.
use generate_image as pl_tool_generate_image;
use pl_agent_tool::{Tool, typed};
use pl_tool_generate_image::{GenerateImage, GeneratedImage, ImageGenerator};
use pl_tool_media_support::{ImageContext, ImageOutputLimits, Media, MediaHost, Retained};
use show_image as pl_tool_show_image;
use std::{
    io::Cursor,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};
use view_image as pl_tool_view_image;

fn png() -> Arc<[u8]> {
    let mut bytes = Cursor::new(Vec::new());
    image::DynamicImage::new_rgb8(20, 10)
        .write_to(&mut bytes, image::ImageFormat::Png)
        .unwrap();
    bytes.into_inner().into()
}

#[derive(Default)]
struct Archive {
    media: Mutex<Vec<Media>>,
    fail: AtomicBool,
}

impl MediaHost for Archive {
    type Reference = usize;
    type Projection = String;
    type Error = std::io::Error;

    async fn retain(&self, media: Media) -> Result<Retained<usize, String>, Self::Error> {
        let mut received = self.media.lock().unwrap();
        let id = received.len();
        received.push(media);
        if self.fail.load(Ordering::SeqCst) {
            return Err(std::io::Error::other("archive unavailable"));
        }
        Ok(Retained {
            reference: id,
            projection: format!("image:{id}"),
        })
    }
}

struct Generator {
    bytes: Arc<[u8]>,
    requests: Arc<Mutex<Vec<(String, bool)>>>,
}

impl ImageGenerator for Generator {
    type Error = std::convert::Infallible;
    async fn generate(
        &self,
        prompt: String,
        transparent: bool,
    ) -> Result<GeneratedImage, Self::Error> {
        self.requests.lock().unwrap().push((prompt, transparent));
        Ok(GeneratedImage {
            bytes: self.bytes.clone(),
            media_type: "image/png".into(),
            revised_prompt: Some("service revision".into()),
        })
    }
}

struct Reader {
    bytes: Arc<[u8]>,
    reads: Arc<Mutex<Vec<(String, usize)>>>,
}
impl pl_tool_view_image::ImageReader for Reader {
    type Error = std::convert::Infallible;
    async fn read(&self, path: String, max_bytes: usize) -> Result<Arc<[u8]>, Self::Error> {
        self.reads.lock().unwrap().push((path, max_bytes));
        Ok(self.bytes.clone())
    }
}

#[tokio::test]
async fn read_normalize_generate_and_select_run_without_product_types() {
    let source = png();
    let archive = Arc::new(Archive::default());
    let reads = Arc::new(Mutex::new(Vec::new()));
    let view = typed::prepare_json()
        .unwrap()
        .attach(pl_tool_view_image::ViewImage::new(archive.clone()));
    let output = view
        .execute(
            r#"{"path":"capture.png"}"#.into(),
            pl_tool_view_image::Context {
                reader: Reader {
                    bytes: source.clone(),
                    reads: reads.clone(),
                },
                image: ImageContext {
                    limits: Some(ImageOutputLimits {
                        max_width: Some(4),
                        max_height: Some(4),
                        media_types: vec!["image/png".into(), "image/jpeg".into()],
                        ..Default::default()
                    }),
                    ..Default::default()
                },
            },
        )
        .await
        .unwrap();
    assert_eq!(output.path, "capture.png");
    assert_eq!((output.model_width, output.model_height), (4, 2));
    assert_eq!(
        reads.lock().unwrap().as_slice(),
        &[("capture.png".into(), pl_tool_media_support::MAX_SOURCE_BYTES)]
    );
    let requests = Arc::new(Mutex::new(Vec::new()));
    let generator = typed::prepare_json().unwrap().attach(GenerateImage::new(
        Generator {
            bytes: source.clone(),
            requests: requests.clone(),
        },
        archive.clone(),
    ));
    let generated = generator
        .execute(
            r#"{"prompt":"  an original scene  ","transparentBackground":true}"#.into(),
            ImageContext::default(),
        )
        .await
        .unwrap();
    assert_eq!(
        requests.lock().unwrap().as_slice(),
        &[("an original scene".into(), true)]
    );
    assert_eq!(generated.prompt, "an original scene");
    assert_eq!(
        generated.revised_prompt.as_deref(),
        Some("service revision")
    );
    assert_eq!(generated.model_dimensions, None);
    {
        let retained = archive.media.lock().unwrap();
        assert_eq!(retained.len(), 2);
        assert_eq!(retained[0].bytes.as_ref(), source.as_ref());
        let variant = retained[0].model_image.as_ref().unwrap();
        assert_eq!(variant.media_type, "image/jpeg");
        assert_eq!(image::load_from_memory(&variant.bytes).unwrap().width(), 4);
        assert_eq!(image::load_from_memory(&variant.bytes).unwrap().height(), 2);
        assert_eq!(retained[1].bytes.as_ref(), source.as_ref());
        assert!(
            retained[1].model_image.is_none(),
            "no-image models still archive the source"
        );
    }
    let show = typed::prepare_json()
        .unwrap()
        .attach(pl_tool_show_image::ShowImage::default());
    let candidates = || {
        vec![
            pl_tool_show_image::ArchivedImage {
                id: "generated".into(),
                image: generated.retained.reference,
            },
            pl_tool_show_image::ArchivedImage {
                id: "viewed".into(),
                image: output.retained.reference,
            },
        ]
    };
    let shown = show
        .execute(r#"{"caption":"  ready  "}"#.into(), candidates())
        .await
        .unwrap();
    assert_eq!(shown.image, 1);
    assert_eq!(shown.caption.as_deref(), Some("ready"));
    let chosen = show
        .execute(r#"{"imageId":"viewed"}"#.into(), candidates())
        .await
        .unwrap();
    assert_eq!(chosen.image, 0);
    assert!(
        show.execute(r#"{"imageId":"unknown"}"#.into(), candidates())
            .await
            .is_err()
    );
    assert!(
        show.execute(
            serde_json::json!({"caption": "图".repeat(241)}).to_string(),
            candidates()
        )
        .await
        .is_err()
    );
    assert!(
        show.execute(r#"{"path":"forbidden.png"}"#.into(), candidates())
            .await
            .is_err()
    );
    view.close().await.unwrap();
    generator.close().await.unwrap();
    show.close().await.unwrap();
}

#[tokio::test]
async fn validation_precedes_service_and_archive_failure_retains_received_bytes_without_retry() {
    let source = png();
    let archive = Arc::new(Archive::default());
    archive.fail.store(true, Ordering::SeqCst);
    let requests = Arc::new(Mutex::new(Vec::new()));
    let generator = typed::prepare_json().unwrap().attach(GenerateImage::new(
        Generator {
            bytes: source.clone(),
            requests: requests.clone(),
        },
        archive.clone(),
    ));
    for input in [
        r#"{"prompt":"  "}"#.to_owned(),
        serde_json::json!({"prompt": "a".repeat(8001)}).to_string(),
        r#"{"prompt":"ok","unknown":true}"#.into(),
    ] {
        assert!(
            generator
                .execute(input, ImageContext::default())
                .await
                .is_err()
        );
    }
    let cancelled = ImageContext::default();
    cancelled.cancellation.cancel();
    assert!(
        generator
            .execute(r#"{"prompt":"ok"}"#.into(), cancelled)
            .await
            .is_err()
    );
    assert!(requests.lock().unwrap().is_empty());
    let error = match generator
        .execute(r#"{"prompt":"ok"}"#.into(), ImageContext::default())
        .await
    {
        Err(typed::InvocationError::Tool(error)) => error,
        _ => panic!("archive failure must be a tool failure"),
    };
    assert_eq!(
        error.observed.as_ref().unwrap().bytes.as_ref(),
        source.as_ref()
    );
    assert!(error.source.downcast_ref::<std::io::Error>().is_some());
    assert_eq!(requests.lock().unwrap().len(), 1);
    assert_eq!(archive.media.lock().unwrap().len(), 1);
}
