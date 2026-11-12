//! Large incremental directory reads share the production foreground connection.
#![cfg(target_os = "linux")]
#[path = "support/helper.rs"]
mod helper;
#[path = "support/remote.rs"]
mod support;
use tokio::io::AsyncReadExt;
#[tokio::test]
async fn large_directory_reader_can_be_cancelled_without_closing_shared_executor()
-> anyhow::Result<()> {
    let helper = support::Helper::start(helper::remote_helper_executable()).await?;
    for index in 0..1000 {
        tokio::fs::write(
            helper
                .root
                .path()
                .join(format!("entry-{index:04}-{}", "x".repeat(180))),
            b"fixture",
        )
        .await?;
    }
    let observed = async {
        let mut reader = helper.files.open_directory(".".into()).await?;
        let first = reader.next().await?.unwrap();
        assert!(first.name.starts_with("entry-"));
        drop(reader);
        let output = helper
            .executor
            .command("/bin/echo")
            .arg("other")
            .output()
            .await?;
        assert_eq!(output.stdout, b"other\n");
        let mut reader = helper.files.open_directory(".".into()).await?;
        let mut names = std::collections::BTreeSet::new();
        while let Some(entry) = reader.next().await? {
            assert!(names.insert(entry.name));
        }
        assert_eq!(names.len(), 1000);
        let path = helper.executor.path(
            helper
                .root
                .path()
                .join(names.first().unwrap())
                .to_str()
                .unwrap(),
        )?;
        let mut bytes = Vec::new();
        helper
            .executor
            .fs()
            .read(&path)
            .await?
            .read_to_end(&mut bytes)
            .await?;
        assert_eq!(bytes, b"fixture");
        anyhow::Ok(())
    }
    .await;
    let closed = helper.close().await;
    observed?;
    closed
}
