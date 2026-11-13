//! Native canonical replies must stay within their lexical workspace root.
#![cfg(windows)]

use pl_remote_helper::Executor;
use tokio::io::AsyncReadExt;

#[tokio::test]
async fn long_canonical_capture_keeps_its_workspace_relative_identity() {
    let directory = tempfile::tempdir().unwrap();
    let root = dunce::canonicalize(directory.path()).unwrap();
    let capture = root.join("nested".repeat(20)).join("capture".repeat(25));
    assert!(capture.as_os_str().len() > 260);
    std::fs::create_dir_all(capture.parent().unwrap()).unwrap();
    std::fs::write(&capture, b"\xff\0confirmed capture").unwrap();

    let executor = Executor::local().unwrap();
    let root = executor.path(root.to_str().unwrap()).unwrap();
    let capture = executor.path(capture.to_str().unwrap()).unwrap();
    let canonical = executor.fs().canonicalize(&capture).await.unwrap();
    assert!(canonical.as_str().starts_with(r"\\?\"));
    let relative = executor.relative_path(&root, &canonical).unwrap().unwrap();
    let joined = executor.join_path(&root, &relative).unwrap();
    assert_eq!(
        executor.fs().canonicalize(&joined).await.unwrap(),
        canonical
    );
    let mut bytes = Vec::new();
    executor
        .fs()
        .read(&joined)
        .await
        .unwrap()
        .read_to_end(&mut bytes)
        .await
        .unwrap();
    assert_eq!(bytes, b"\xff\0confirmed capture");

    let neighbor = executor
        .path(format!("{}-outside\\capture", root.as_str()))
        .unwrap();
    assert_eq!(executor.relative_path(&root, &neighbor).unwrap(), None);
    let long_neighbor = executor
        .path(format!(
            r"\\?\{}-outside\{}",
            root.as_str(),
            "capture".repeat(50)
        ))
        .unwrap();
    assert_eq!(executor.relative_path(&root, &long_neighbor).unwrap(), None);
    assert_eq!(executor.relative_path(&canonical, &root).unwrap(), None);
    executor.close().await.unwrap();
}
