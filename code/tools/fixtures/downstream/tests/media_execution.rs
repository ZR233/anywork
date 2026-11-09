//! Independent consumers exercise actual tools; the fixture only supplies bytes and storage.
use generate_image::{GenerateImage, GeneratedImage, ImageGenerator};
use media::{generate_image, show_files, view_image};
use pl_agent_tool::{Tool, typed};
use pl_tool_media_support::{ImageContext, ImageOutputLimits, Media, MediaHost, Retained};
use std::{
    io::Cursor,
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, Ordering},
    },
};

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
impl view_image::ImageReader for Reader {
    type Error = std::convert::Infallible;
    async fn read(&self, path: String, max_bytes: usize) -> Result<Arc<[u8]>, Self::Error> {
        self.reads.lock().unwrap().push((path, max_bytes));
        Ok(self.bytes.clone())
    }
}

struct DisplaySource {
    reads: Arc<Mutex<Vec<(String, usize)>>>,
}

impl show_files::FileSource for DisplaySource {
    type Reference = usize;
    type Error = std::io::Error;

    async fn stat(&self, path: &str) -> Result<show_files::FileStat, Self::Error> {
        if path == "denied" {
            return Err(std::io::Error::new(
                std::io::ErrorKind::PermissionDenied,
                "denied",
            ));
        }
        Ok(show_files::FileStat {
            is_file: path != "directory",
            len: Some(if path == "large" {
                show_files::MAX_SOURCE_BYTES as u64 + 1
            } else {
                3
            }),
        })
    }

    async fn local_file_path(&self, path: &str) -> Result<Option<String>, Self::Error> {
        Ok((path == "local.txt").then(|| "/verified/local.txt".into()))
    }

    async fn read_bytes(&self, path: &str, max_bytes: usize) -> Result<Arc<[u8]>, Self::Error> {
        self.reads.lock().unwrap().push((path.into(), max_bytes));
        Ok(Arc::from(&b"abc"[..]))
    }

    async fn archived_file(&self, id: &str) -> Result<show_files::File<usize>, Self::Error> {
        if id != "saved" {
            return Err(std::io::Error::other("not a member of the frozen archive"));
        }
        Ok(show_files::File {
            resource: 42,
            filename: "saved.pdf".into(),
            modality: show_files::Modality::File,
            origin: show_files::Origin::Archive,
        })
    }
}

#[tokio::test]
async fn show_files_preserves_order_exact_bytes_sources_and_partial_failures() {
    let archive = Arc::new(Archive::default());
    let reads = Arc::new(Mutex::new(Vec::new()));
    let show = typed::prepare_json()
        .unwrap()
        .attach(show_files::ShowFiles::new(archive.clone()));
    let context = || show_files::Context {
        source: DisplaySource {
            reads: reads.clone(),
        },
        cancellation: Default::default(),
    };
    // Invalid requests must fail before touching sources or retention.
    for args in [
        serde_json::json!({"files": []}),
        serde_json::json!({"files": [{"kind":"workspace","path":" "}]}),
        serde_json::json!({"files": [{"kind":"attachment","attachmentId":""}]}),
        serde_json::json!({"files": [{"kind":"workspace","path":"local.txt"}], "caption":"图".repeat(241)}),
        serde_json::json!({"files": [{"kind":"workspace","path":"local.txt","extra":true}]}),
    ] {
        assert!(show.execute(args.to_string(), context()).await.is_err());
    }
    let cancelled = context();
    cancelled.cancellation.cancel();
    assert!(
        show.execute(
            r#"{"files":[{"kind":"workspace","path":"local.txt"}]}"#.into(),
            cancelled,
        )
        .await
        .is_err()
    );
    assert!(reads.lock().unwrap().is_empty());
    assert!(archive.media.lock().unwrap().is_empty());

    let output = show
        .execute(
            serde_json::json!({
                "caption":"  displayed  ",
                "files":[
                    {"kind":"workspace","path":"local.txt"},
                    {"kind":"workspace","path":"denied"},
                    {"kind":"workspace","path":"remote.txt"},
                    {"kind":"attachment","attachmentId":"saved"},
                    {"kind":"workspace","path":"large"},
                    {"kind":"workspace","path":"directory"},
                    {"kind":"workspace","path":"corrupt.png"},
                    {"kind":"attachment","attachmentId":"foreign"}
                ]
            })
            .to_string(),
            context(),
        )
        .await
        .unwrap();
    let receipt = serde_json::to_value(&output).unwrap();
    assert_eq!(receipt["caption"], "displayed");
    let files = receipt["files"].as_array().unwrap();
    assert_eq!(files.len(), 8);
    assert_eq!(files[0]["status"], "ready");
    assert_eq!(
        files[0]["origin"],
        serde_json::json!({"kind":"local","path":"/verified/local.txt"})
    );
    assert_eq!(files[0]["modality"], "file");
    assert_eq!(files[1]["status"], "failed");
    assert_eq!(files[2]["origin"], serde_json::json!({"kind":"remote"}));
    assert_eq!(files[3]["origin"], serde_json::json!({"kind":"archive"}));
    assert_eq!(files[3]["resource"], 42);
    assert_eq!(files[3]["filename"], "saved.pdf");
    for file in &files[4..] {
        assert_eq!(file["status"], "failed");
    }
    assert!(files[4]["message"].as_str().unwrap().contains("50 MiB"));
    assert!(
        files[5]["message"]
            .as_str()
            .unwrap()
            .contains("regular file")
    );
    assert!(
        files[6]["message"]
            .as_str()
            .unwrap()
            .contains("image header")
    );
    assert!(
        files[7]["message"]
            .as_str()
            .unwrap()
            .contains("frozen archive")
    );
    assert_eq!(
        reads.lock().unwrap().as_slice(),
        &[
            ("/verified/local.txt".into(), show_files::MAX_SOURCE_BYTES),
            ("remote.txt".into(), show_files::MAX_SOURCE_BYTES),
            ("corrupt.png".into(), show_files::MAX_SOURCE_BYTES),
        ]
    );
    {
        let retained = archive.media.lock().unwrap();
        assert_eq!(retained.len(), 2);
        for media in retained.iter() {
            assert_eq!(media.bytes.as_ref(), b"abc");
            assert_eq!(media.media_type, "text/plain");
            assert!(media.model_image.is_none());
        }
    }
    // A retention failure remains a per-file failure; no retry or success reference.
    archive.fail.store(true, Ordering::SeqCst);
    let output = show
        .execute(
            r#"{"files":[{"kind":"workspace","path":"remote.txt"}]}"#.into(),
            context(),
        )
        .await
        .unwrap();
    assert!(
        matches!(&output.files[0], show_files::FileResult::Failed { message, .. } if message == "archive unavailable")
    );
    assert_eq!(archive.media.lock().unwrap().len(), 3);
    assert_eq!(reads.lock().unwrap().len(), 4);
    show.close().await.unwrap();
}

#[tokio::test]
async fn read_normalize_and_generate_run_without_product_types() {
    let source = png();
    let archive = Arc::new(Archive::default());
    let reads = Arc::new(Mutex::new(Vec::new()));
    let view = typed::prepare_json()
        .unwrap()
        .attach(view_image::ViewImage::new(archive.clone()));
    let output = view
        .execute(
            r#"{"path":"capture.png"}"#.into(),
            view_image::Context {
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
        &[(
            "capture.png".into(),
            pl_tool_media_support::MAX_SOURCE_BYTES
        )]
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
    view.close().await.unwrap();
    generator.close().await.unwrap();
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
