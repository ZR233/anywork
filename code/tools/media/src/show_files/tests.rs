use super::*;
use pl_tool_media_support::Retained;
use std::io;

struct Remote;
impl FileSource for Remote {
    type Reference = String;
    type Deferred = String;
    type Error = io::Error;

    async fn stat(&self, _: &str) -> Result<FileStat, io::Error> {
        Ok(FileStat { is_file: true })
    }
    async fn local_file_path(&self, _: &str) -> Result<Option<String>, io::Error> {
        Ok(None)
    }
    async fn defer_file(&self, path: &str) -> Result<String, io::Error> {
        Ok(format!("frozen:{path}"))
    }
    async fn read_bytes(&self, path: &str) -> Result<Arc<[u8]>, io::Error> {
        assert!(
            matches!(path, "notes.md" | "NOTES.MARKDOWN"),
            "read body of {path}"
        );
        Ok(Arc::from(b"# exact\r\n".as_slice()))
    }
    async fn archived_file(&self, _: &str) -> Result<File<String>, io::Error> {
        unreachable!()
    }
}
struct Host;
impl MediaHost for Host {
    type Reference = String;
    type Projection = ();
    type Error = io::Error;
    async fn retain(&self, media: Media) -> Result<Retained<String, ()>, io::Error> {
        assert_eq!(&*media.bytes, b"# exact\r\n");
        assert_eq!(media.media_type, "text/markdown");
        Ok(Retained {
            reference: "archive".into(),
            projection: (),
        })
    }
}

#[tokio::test]
async fn remote_nonpreviews_never_read_bodies_and_markdown_retains_originals() {
    let output = ShowFiles::new(Arc::new(Host))
        .execute(
            Input {
                caption: None,
                files: [
                    "huge.bin",
                    "report.pdf",
                    "drawing.svg",
                    "movie.mp4",
                    "notes.md",
                    "NOTES.MARKDOWN",
                ]
                .map(|path| Source::Workspace { path: path.into() })
                .into(),
            },
            Context {
                source: Remote,
                cancellation: Default::default(),
            },
        )
        .await
        .unwrap();
    for (index, name) in ["huge.bin", "report.pdf", "drawing.svg", "movie.mp4"]
        .iter()
        .enumerate()
    {
        assert!(
            matches!(&output.files[index], FileResult::Deferred { filename, target }
            if filename == name && target == &format!("frozen:{name}"))
        );
    }
    assert!(
        output.files[4..]
            .iter()
            .all(|f| matches!(f, FileResult::Ready(_)))
    );
}

#[tokio::test]
async fn network_validation_is_per_item_and_performs_no_file_io() {
    let output = ShowFiles::new(Arc::new(Host))
        .execute(
            Input {
                caption: None,
                files: vec![
                    Source::NetworkImage {
                        url: "https://example.org/picture.png?signature=x".into(),
                    },
                    Source::NetworkImage {
                        url: "http://example.org/picture.png".into(),
                    },
                    Source::NetworkImage {
                        url: "https://example.org/second.png".into(),
                    },
                ],
            },
            Context {
                source: Remote,
                cancellation: Default::default(),
            },
        )
        .await
        .unwrap();
    assert!(
        matches!(&output.files[0], FileResult::NetworkImage { filename, url }
        if filename == "picture.png" && url == "https://example.org/picture.png?signature=x")
    );
    assert!(matches!(&output.files[1], FileResult::Failed { .. }));
    assert!(matches!(&output.files[2], FileResult::NetworkImage { .. }));
}

#[test]
fn network_url_limits_apply_before_parser_normalization() {
    for input in [
        "",
        "file:///tmp/image.png",
        "http://example.org/i.png",
        "https://",
        "https://user@example.org/i",
        "https://@example.org/i",
        "https:\\@example.org/i",
        "https://:pass@example.org/i",
        "https://example.org/\ni.png",
        "https://example.org/\u{7f}i",
        "https://example.org/\u{85}i",
    ] {
        assert!(
            validate_network_image_url(input).is_err(),
            "accepted {input:?}"
        );
    }
    let mut boundary = "https://example.org/".to_owned();
    boundary.extend(std::iter::repeat_n('x', 8192 - boundary.len()));
    assert!(validate_network_image_url(&boundary).is_ok());
    boundary.push('x');
    assert!(validate_network_image_url(&boundary).is_err());
    assert!(validate_network_image_url("https://example.org/i.png").is_ok());
}
