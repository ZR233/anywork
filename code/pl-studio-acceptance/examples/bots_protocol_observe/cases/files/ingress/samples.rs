//! Standard media samples. Display names are independent user data, not paths
//! to the generator's output. Different originals deliberately share one name.

use anyhow::{Context, Result, ensure};
use pl_provider_fixture::feishu::media::ResourceKind;
use std::{
    path::Path,
    process::{Command, Stdio},
};

pub(super) struct Sample {
    pub id: &'static str,
    pub name: &'static str,
    pub kind: ResourceKind,
    pub mime: &'static str,
    pub bytes: Vec<u8>,
}

impl Sample {
    /// Image/audio receive wire carries no display filename. Their documented
    /// host-chosen names are checked through the reliable attachment DTO, not
    /// an invented provider image-field or a synthetic download header.
    pub fn display_name(&self) -> Option<&str> {
        match self.kind {
            ResourceKind::Image | ResourceKind::Audio => None,
            ResourceKind::File | ResourceKind::Media => Some(self.name),
        }
    }
}

pub(super) fn all(output: &Path) -> Result<Vec<Sample>> {
    let ordinary = b"ordinary original\nD2-file-tail\n".to_vec();
    let mut opaque = vec![0x80; ordinary.len()];
    opaque[0] = 0;
    Ok(vec![
        Sample {
            id: "om_media_image",
            name: "小图 原件.png",
            kind: ResourceKind::Image,
            mime: "image/png",
            bytes: image(output, "small.png", "color=c=red:s=16x12", false)?,
        },
        Sample {
            id: "om_media_file",
            name: "报告 共享名.txt",
            kind: ResourceKind::File,
            mime: "text/plain",
            bytes: ordinary,
        },
        Sample {
            id: "om_media_noext",
            name: "无扩展 文稿",
            kind: ResourceKind::File,
            mime: "application/octet-stream",
            bytes: b"no extension original\n".to_vec(),
        },
        Sample {
            id: "om_media_unknown",
            name: "报告 共享名.txt",
            kind: ResourceKind::File,
            mime: "application/octet-stream",
            bytes: opaque,
        },
        Sample {
            id: "om_media_audio",
            name: "声音 样本.wav",
            kind: ResourceKind::Audio,
            mime: "audio/wav",
            bytes: audio(output)?,
        },
        Sample {
            id: "om_media_video",
            name: "视频 样本.mp4",
            kind: ResourceKind::Media,
            mime: "video/mp4",
            bytes: image(output, "track.mp4", "color=c=green:s=32x24:r=5", true)?,
        },
        Sample {
            id: "om_media_corrupt",
            name: "容器 损坏.mp4",
            kind: ResourceKind::File,
            mime: "video/mp4",
            bytes: b"\0\0\0\x18ftypmp42\0\0\0\0mp42isomBROKEN-no-video-track".to_vec(),
        },
        Sample {
            id: "om_media_large",
            name: "大图 原件.png",
            kind: ResourceKind::Image,
            mime: "image/png",
            bytes: image(output, "large.png", "testsrc=size=512x256:rate=1", false)?,
        },
    ])
}

pub(super) fn image(output: &Path, name: &str, source: &str, video: bool) -> Result<Vec<u8>> {
    let inputs = output.join("inputs");
    std::fs::create_dir_all(&inputs)?;
    let path = inputs.join(name);
    let mut command = Command::new("ffmpeg");
    command.args(["-nostdin", "-v", "error", "-f", "lavfi", "-i", source]);
    if video {
        command.args(["-t", "0.4", "-c:v", "mpeg4", "-pix_fmt", "yuv420p"]);
    } else {
        command.args(["-frames:v", "1", "-threads", "1"]);
    }
    generate(&mut command, &path)
}

fn audio(output: &Path) -> Result<Vec<u8>> {
    generate(
        Command::new("ffmpeg").args([
            "-nostdin",
            "-v",
            "error",
            "-f",
            "lavfi",
            "-i",
            "sine=frequency=440:duration=0.1",
            "-c:a",
            "pcm_s16le",
        ]),
        &output.join("inputs/audio.wav"),
    )
}

fn generate(command: &mut Command, path: &Path) -> Result<Vec<u8>> {
    let result = command
        .arg("-y")
        .arg(path)
        .stdin(Stdio::null())
        .output()
        .context("ffmpeg is required to produce standard real media samples")?;
    ensure!(
        result.status.success(),
        "ffmpeg failed: {}",
        String::from_utf8_lossy(&result.stderr)
    );
    let bytes = std::fs::read(path)?;
    ensure!(
        !bytes.is_empty() && bytes.len() < 1_000_000,
        "generated media is empty or unexpectedly large"
    );
    Ok(bytes)
}

pub(super) fn dimensions(path: &Path, max_width: u32, max_height: u32) -> Result<()> {
    #[derive(serde::Deserialize)]
    struct Probe {
        streams: Vec<Dimensions>,
    }
    #[derive(serde::Deserialize)]
    struct Dimensions {
        width: u32,
        height: u32,
    }
    let output = Command::new("ffprobe")
        .args([
            "-v",
            "error",
            "-select_streams",
            "v:0",
            "-show_entries",
            "stream=width,height",
            "-of",
            "json",
        ])
        .arg(path)
        .output()?;
    ensure!(
        output.status.success(),
        "ffprobe could not read the actual derived image"
    );
    let probe: Probe = serde_json::from_slice(&output.stdout)?;
    ensure!(
        probe.streams.len() == 1
            && probe.streams[0].width <= max_width
            && probe.streams[0].height <= max_height,
        "native image derivative exceeds configured dimensions"
    );
    Ok(())
}
