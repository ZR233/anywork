use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};

use pl_patch::{
    PatchBackend, PatchError, PatchFileChange, PatchOutcome, PatchPathDisplay, PatchResult,
    apply_patch,
};
use tempfile::TempDir;

struct TestBackend {
    directory: TempDir,
}

impl TestBackend {
    fn new() -> Self {
        Self {
            directory: tempfile::tempdir().unwrap(),
        }
    }

    fn path(&self, path: &str) -> PathBuf {
        self.directory.path().join(path)
    }

    fn write(&self, path: &str, content: &str) {
        let path = self.path(path);
        fs::create_dir_all(path.parent().unwrap()).unwrap();
        fs::write(path, content).unwrap();
    }

    fn read(&self, path: &str) -> String {
        fs::read_to_string(self.path(path)).unwrap()
    }

    async fn apply(&self, body: &str) -> PatchOutcome {
        apply_patch(&wrap_patch(body), self).await.unwrap()
    }
}

impl PatchPathDisplay for TestBackend {
    fn display_path(&self, path: &Path) -> String {
        path.strip_prefix(self.directory.path())
            .unwrap()
            .display()
            .to_string()
    }
}

impl PatchBackend for TestBackend {
    async fn resolve_existing(&self, path: &str) -> PatchResult<PathBuf> {
        let path = self.path(path);
        fs::metadata(&path).map_err(PatchError::new)?;
        Ok(path)
    }

    async fn resolve_for_write(&self, path: &str) -> PatchResult<PathBuf> {
        Ok(self.path(path))
    }

    async fn reject_symlink_write(&self, path: &Path) -> PatchResult<()> {
        match fs::symlink_metadata(path) {
            Ok(metadata) if metadata.is_symlink() => Err(PatchError::new("symlink write rejected")),
            Ok(_) => Ok(()),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(()),
            Err(error) => Err(PatchError::new(error)),
        }
    }

    async fn ensure_file(&self, path: &Path) -> PatchResult<()> {
        if fs::metadata(path).map_err(PatchError::new)?.is_file() {
            Ok(())
        } else {
            Err(PatchError::new("expected a file"))
        }
    }

    async fn read_to_string(&self, path: &Path) -> PatchResult<String> {
        fs::read_to_string(path).map_err(PatchError::new)
    }

    async fn read_optional_text(&self, path: &Path) -> PatchResult<Option<String>> {
        match fs::read_to_string(path) {
            Ok(content) => Ok(Some(content)),
            Err(error) if error.kind() == ErrorKind::NotFound => Ok(None),
            Err(error) => Err(PatchError::new(error)),
        }
    }

    async fn create_parent_dirs(&self, path: &Path) -> PatchResult<()> {
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(PatchError::new)?;
        }
        Ok(())
    }

    async fn write_text(&self, path: &Path, content: &str) -> PatchResult<()> {
        fs::write(path, content).map_err(PatchError::new)
    }

    async fn remove_file(&self, path: &Path) -> PatchResult<()> {
        fs::remove_file(path).map_err(PatchError::new)
    }
}

fn wrap_patch(body: &str) -> String {
    format!("*** Begin Patch\n{body}\n*** End Patch")
}

async fn assert_update(original: &str, body: &str, expected: &str) {
    let backend = TestBackend::new();
    backend.write("file.txt", original);

    let outcome = backend.apply(body).await;

    assert_eq!(backend.read("file.txt"), expected);
    assert_eq!(
        outcome.file_changes(),
        vec![PatchFileChange::Update {
            path: backend.path("file.txt"),
        }]
    );
    assert_eq!(
        outcome.summary(&backend),
        "Success. Updated the following files:\nM file.txt\n"
    );
}

async fn assert_rejected(patch: &str, expected_message: &str) {
    let backend = TestBackend::new();
    backend.write("file.txt", "original\n");

    let error = apply_patch(patch, &backend).await.unwrap_err();

    assert!(error.message().contains(expected_message), "{error}");
    assert_eq!(backend.read("file.txt"), "original\n");
}

// 来源：codex apply-patch/src/lib.rs 的同名 test_* 用例，版本 970111f6cb。
#[tokio::test]
async fn codex_add_file_hunk_creates_file_with_contents() {
    let backend = TestBackend::new();

    let outcome = backend
        .apply("*** Add File: nested/add.txt\n+ab\n+\n+  cd  \n+\tef\t")
        .await;

    assert_eq!(backend.read("nested/add.txt"), "ab\n\n  cd  \n\tef\t\n");
    assert_eq!(
        outcome.file_changes(),
        vec![PatchFileChange::Add {
            path: backend.path("nested/add.txt"),
        }]
    );
    assert_eq!(
        outcome.summary(&backend),
        "Success. Updated the following files:\nA nested/add.txt\n"
    );
}

#[tokio::test]
async fn codex_delete_file_hunk_removes_file() {
    let backend = TestBackend::new();
    backend.write("delete.txt", "x");

    let outcome = backend.apply("*** Delete File: delete.txt").await;

    assert!(!backend.path("delete.txt").exists());
    assert_eq!(
        outcome.file_changes(),
        vec![PatchFileChange::Delete {
            path: backend.path("delete.txt"),
        }]
    );
    assert_eq!(
        outcome.summary(&backend),
        "Success. Updated the following files:\nD delete.txt\n"
    );
}

#[tokio::test]
async fn codex_update_file_hunk_modifies_content() {
    assert_update(
        "foo\nbar\n",
        "*** Update File: file.txt\n@@\n foo\n-bar\n+baz",
        "foo\nbaz\n",
    )
    .await;
}

#[tokio::test]
async fn codex_update_file_hunk_can_move_file() {
    let backend = TestBackend::new();
    backend.write("source.txt", "line\n");
    backend.write("nested/destination.txt", "overwritten\n");

    let outcome = backend
        .apply(
            "*** Update File: source.txt\n*** Move to: nested/destination.txt\n@@\n-line\n+line2",
        )
        .await;

    assert!(!backend.path("source.txt").exists());
    assert_eq!(backend.read("nested/destination.txt"), "line2\n");
    assert_eq!(
        outcome.file_changes(),
        vec![PatchFileChange::Move {
            source: backend.path("source.txt"),
            target: backend.path("nested/destination.txt"),
        }]
    );
    assert_eq!(
        outcome.summary(&backend),
        "Success. Updated the following files:\nM nested/destination.txt\n"
    );
}

#[tokio::test]
async fn codex_multiple_update_chunks_apply_to_single_file() {
    assert_update(
        "foo\nbar\nbaz\nqux\n",
        "*** Update File: file.txt\n@@\n foo\n-bar\n+BAR\n@@ baz\n-qux\n+QUX",
        "foo\nBAR\nbaz\nQUX\n",
    )
    .await;
}

#[tokio::test]
async fn codex_update_file_hunk_interleaved_changes() {
    assert_update(
        "a\nb\nc\nd\ne\nf\n",
        "*** Update File: file.txt\n@@\n a\n-b\n+B\n c\n+inserted\n d\n-e\n+E\n f\n+g\n*** End of File",
        "a\nB\nc\ninserted\nd\nE\nf\ng\n",
    )
    .await;
}

#[tokio::test]
async fn codex_pure_addition_chunk_followed_by_removal() {
    assert_update(
        "line1\nline2\nline3\n",
        "*** Update File: file.txt\n@@\n+after-context\n+second-line\n@@\n line1\n-line2\n-line3",
        "line1\nafter-context\nsecond-line\n",
    )
    .await;
}

#[tokio::test]
async fn codex_update_line_with_unicode_dash() {
    for (replacement, expected) in [
        ("import asyncio  # HELLO", "import asyncio  # HELLO\n"),
        (
            "import asyncio  # local import - avoids top-level dep",
            "import asyncio  # local import - avoids top-level dep\n",
        ),
    ] {
        assert_update(
            "import asyncio  # local import \u{2013} avoids top\u{2011}level dep\n",
            &format!(
                "*** Update File: file.txt\n@@\n-import asyncio  # local import - avoids top-level dep\n+{replacement}"
            ),
            expected,
        )
        .await;
    }
}

// 来源：codex apply-patch/src/file_update_tests.rs 的同名用例，改从公开入口断言文件内容。
#[tokio::test]
async fn codex_unified_diff_first_line_replacement() {
    assert_update(
        "foo\n    bar  \nbaz\n",
        "*** Update File: file.txt\n@@\n-foo\n+FOO\n bar",
        "FOO\n    bar  \nbaz\n",
    )
    .await;
}

#[tokio::test]
async fn codex_unified_diff_last_line_replacement() {
    assert_update(
        "foo\n    bar  \nbaz\n",
        "*** Update File: file.txt\n@@\n foo\n bar\n-baz\n+BAZ",
        "foo\n    bar  \nBAZ\n",
    )
    .await;
}

#[tokio::test]
async fn codex_unified_diff_insert_at_eof() {
    assert_update(
        "foo\nbar\nbaz\n",
        "*** Update File: file.txt\n@@\n+quux\n*** End of File",
        "foo\nbar\nbaz\nquux\n",
    )
    .await;
}

#[tokio::test]
async fn codex_unified_diff_interleaved_changes() {
    assert_update(
        "a\nb\nc\nd\ne\nf\n",
        "*** Update File: file.txt\n@@\n a\n-b\n+B\n@@\n d\n-e\n+E\n@@\n f\n+g\n*** End of File",
        "a\nB\nc\nd\nE\nf\ng\n",
    )
    .await;
}

#[tokio::test]
async fn indent_increase_only() {
    assert_update(
        "fn a() {\n    foo();\n}\n",
        "*** Update File: file.txt\n@@\n fn a() {\n-    foo();\n+        foo();\n }",
        "fn a() {\n        foo();\n}\n",
    )
    .await;
}

#[tokio::test]
async fn indent_decrease_only() {
    assert_update(
        "fn a() {\n    foo();\n}\n",
        "*** Update File: file.txt\n@@\n fn a() {\n-    foo();\n+foo();\n }",
        "fn a() {\nfoo();\n}\n",
    )
    .await;
}

#[tokio::test]
async fn tab_indent_increase() {
    assert_update(
        "fn a() {\n\tfoo();\n}\n",
        "*** Update File: file.txt\n@@\n fn a() {\n-\tfoo();\n+\t\tfoo();\n }",
        "fn a() {\n\t\tfoo();\n}\n",
    )
    .await;
}

#[tokio::test]
async fn indent_change_with_content_change() {
    assert_update(
        "fn a() {\n    foo();\n}\n",
        "*** Update File: file.txt\n@@\n fn a() {\n-    foo();\n+        bar();\n }",
        "fn a() {\n        bar();\n}\n",
    )
    .await;
}

#[tokio::test]
async fn context_line_indent_mismatch_keeps_file_text() {
    assert_update(
        "    marker  \n    foo();\n",
        "*** Update File: file.txt\n@@\n marker\n-    foo();\n+        foo();",
        "    marker  \n        foo();\n",
    )
    .await;
}

#[tokio::test]
async fn trailing_whitespace_mismatch_does_not_change_written_lines() {
    assert_update(
        "    foo();   \n",
        "*** Update File: file.txt\n@@\n-    foo();\n+    foo();  ",
        "    foo();  \n",
    )
    .await;
}

#[tokio::test]
async fn parse_rejects_unified_diff_headers() {
    // 共同拒绝标准 diff 头；anywork 差异仅在于针对该输入的诊断文案。
    // 本地依据：code/pl-patch/src/parse.rs:241-242；Codex streaming_parser.rs:187-196 使用通用头部错误。
    for header in ["--- a/file.txt", "+++ b/file.txt"] {
        assert_rejected(
            &wrap_patch(header),
            "standard unified diff headers are not supported",
        )
        .await;
    }
}

#[tokio::test]
async fn parse_rejects_unknown_metadata_header() {
    // 共同拒绝未知元数据头；anywork 差异仅在于针对 `*** File:` 的诊断文案。
    // 本地依据：code/pl-patch/src/parse.rs:243-244；Codex streaming_parser.rs:187-196 使用通用头部错误。
    assert_rejected(
        &wrap_patch("*** File: file.txt"),
        "'*** File:' metadata headers are not supported",
    )
    .await;
}

#[tokio::test]
async fn parse_rejects_natural_language_instruction() {
    // 共同拒绝自然语言编辑指令；anywork 差异仅在于针对该输入的诊断文案。
    // 本地依据：code/pl-patch/src/parse.rs:245-249；Codex streaming_parser.rs:187-196 使用通用头部错误。
    assert_rejected(
        &wrap_patch("Insert after original"),
        "natural-language edit instructions are not supported",
    )
    .await;
}

#[tokio::test]
async fn parse_rejects_multiple_patch_blocks() {
    // 共同拒绝多补丁块；anywork 差异仅在于明确指出多个块的诊断文案。
    // 本地依据：code/pl-patch/src/parse.rs:194-197；Codex streaming_parser.rs:369-376 拒绝结束标记后的内容。
    let first = wrap_patch("*** Add File: first.txt\n+first");
    let second = wrap_patch("*** Add File: second.txt\n+second");
    assert_rejected(&format!("{first}\n{second}"), "multiple patch blocks").await;
}

#[tokio::test]
async fn parse_accepts_environment_id_preamble() {
    // 与 Codex 兼容的共同契约（Codex parser.rs 同样支持 `environment_id?` 前导）。
    // 本地依据：code/pl-patch/src/parse.rs:91-99；对照 Codex parser.rs:6、streaming_parser.rs:85-100。
    let backend = TestBackend::new();

    backend
        .apply("*** Environment ID: main\n*** Add File: hello.txt\n+hello")
        .await;

    assert_eq!(backend.read("hello.txt"), "hello\n");
}

#[tokio::test]
async fn parse_accepts_heredoc_wrapper() {
    let body = "*** Update File: file.txt\n@@\n-original\n+updated";
    let patch = wrap_patch(body);
    let backend = TestBackend::new();
    backend.write("file.txt", "original\n");

    apply_patch(&format!("<<'EOF'\n{patch}\nEOF"), &backend)
        .await
        .unwrap();

    assert_eq!(backend.read("file.txt"), "updated\n");
    // 接受完整 heredoc、拒绝缺失 EOF 是共同契约；anywork 差异仅在于缺失 EOF 的诊断文案。
    // 本地依据：code/pl-patch/src/parse.rs:226-229；Codex parser.rs:242-249 保留原始边界错误。
    assert_rejected(&format!("<<'EOF'\n{patch}"), "missing closing EOF marker").await;
}

#[tokio::test]
async fn failures_keep_partial_application_summary() {
    let backend = TestBackend::new();
    backend.write("file.txt", "original\n");
    let patch = wrap_patch(
        "*** Add File: first.txt\n+applied\n*** Update File: file.txt\n@@\n-missing\n+updated",
    );

    let error = apply_patch(&patch, &backend).await.unwrap_err();

    assert_eq!(backend.read("first.txt"), "applied\n");
    assert_eq!(backend.read("file.txt"), "original\n");
    // anywork 差异：部分应用摘要与重试指引采用本地文案，Codex 对应文案不同。
    // 本地依据：code/pl-patch/src/error.rs:5（PATCH_RETRY_GUIDANCE）
    // 与 code/pl-patch/src/outcome.rs:99-101（failure_suffix）；下方只断言本地文案。
    for message in [
        "failed to find expected lines",
        "Changes applied before failure:\nA first.txt (8 bytes)",
        "Recovery: read the target file again, then retry with a smaller Codex-style patch",
        "Do not repeat the same failed patch.",
    ] {
        assert!(error.message().contains(message), "{error}");
    }
    assert!(!error.message().contains("Success."), "{error}");
}

#[tokio::test]
async fn lenient_unprefixed_context_line_is_treated_as_context() {
    // anywork 差异：无空格前缀的非空行也作为上下文参与定位，Codex 会拒绝。
    // 本地依据：code/pl-patch/src/parse.rs:299-304；对照 Codex streaming_parser.rs:351-367。
    assert_update(
        "    marker  \nold\n",
        "*** Update File: file.txt\n@@\nmarker\n-old\n+new",
        "    marker  \nnew\n",
    )
    .await;
}

#[tokio::test]
async fn json_property_key_preserved_context_matching() {
    // anywork 差异：同名 JSON 属性的上下文值可以不同，文件原值与空白仍保留。
    // 本地依据：code/pl-patch/src/matching.rs:112-127、code/pl-patch/src/apply.rs:228-258。
    // 已对照 Codex seek_sequence.rs:33-64：逐行比较文本，不按 JSON 属性键匹配。
    let backend = TestBackend::new();
    backend.write(
        "settings.json",
        "{\n    \"name\": \"actual\",  \n  \"enabled\": false\n}\n",
    );

    backend
        .apply(
            "*** Update File: settings.json\n@@\n {\n   \"name\": \"expected\",\n-  \"enabled\": false\n+    \"enabled\": true\n }",
        )
        .await;

    assert_eq!(
        backend.read("settings.json"),
        "{\n    \"name\": \"actual\",  \n    \"enabled\": true\n}\n"
    );
}

#[tokio::test]
async fn duplicated_edge_context_keeps_indices_aligned() {
    // anywork 差异：重复边缘上下文可以缩短后匹配单行文件。
    // 本地依据：code/pl-patch/src/apply.rs:263-301；Codex file_update.rs:102-122、154-160
    // 仅尝试原序列及尾空行缩短，没有重复边缘候选。
    for (original, body, expected) in [
        (
            "edge\n",
            "*** Update File: file.txt\n@@\n edge\n+inserted\n edge",
            "inserted\nedge\n",
        ),
        (
            "    edge  \n",
            "*** Update File: file.txt\n@@\n+edge\n edge\n edge",
            "    edge  \nedge\n",
        ),
    ] {
        assert_update(original, body, expected).await;
    }
}

#[tokio::test]
async fn trailing_empty_context_keeps_indices_aligned() {
    // 与 Codex 兼容的共同契约：完全空行是上下文，尾部空行可缩短匹配。
    // 本地依据：code/pl-patch/src/parse.rs:299-304、code/pl-patch/src/apply.rs:201-210。
    // 对照 Codex streaming_parser.rs:307-315、file_update.rs:108-122。
    for (original, body, expected) in [
        (
            "    marker  \nold\n",
            "*** Update File: file.txt\n@@\n marker\n-old\n+new\n",
            "    marker  \nnew\n",
        ),
        (
            "    marker  \n \nold\n",
            "*** Update File: file.txt\n@@\n marker\n\n-old\n+new",
            "    marker  \n \nnew\n",
        ),
    ] {
        assert_update(original, body, expected).await;
    }
}

#[tokio::test]
async fn json_property_replacement_requires_old_value_match() {
    // 与 Codex 兼容的共同契约：删除行须匹配旧值；对照 Codex seek_sequence.rs:33-64。
    // 本地 JSON key 放宽仅限显式上下文，依据：code/pl-patch/src/matching.rs:112-127、code/pl-patch/src/apply.rs:228-258。
    // 本地失败/重试文案：code/pl-patch/src/apply.rs:164-168、code/pl-patch/src/error.rs:5。
    let backend = TestBackend::new();
    let original = "{\n  \"name\": \"actual\",\n  \"enabled\": false\n}\n";
    backend.write("settings.json", original);
    let patch = wrap_patch(
        "*** Update File: settings.json\n@@\n {\n-  \"name\": \"expected\",\n+    \"name\": \"expected\",\n   \"enabled\": false\n }",
    );

    let error = apply_patch(&patch, &backend).await.unwrap_err();

    assert!(
        error.message().contains("failed to find expected lines"),
        "{error}"
    );
    assert!(
        error
            .message()
            .contains("Recovery: read the target file again"),
        "{error}"
    );
    assert_eq!(backend.read("settings.json"), original);
}

#[tokio::test]
async fn duplicated_edge_candidate_rejects_deleted_edge_lines() {
    // anywork 本地差异：重复边缘候选仅限真实上下文行，删除行不能因同文而缩短。
    // 本地依据：code/pl-patch/src/apply.rs:267-271；对照 Codex file_update.rs:102-122。
    // Codex 只有原序列与尾空行缩短，没有重复边缘候选。
    let backend = TestBackend::new();
    let original = "edge\n";
    backend.write("file.txt", original);
    let patch = wrap_patch("*** Update File: file.txt\n@@\n-edge\n+edge\n-edge\n+inserted\n+edge");

    let error = apply_patch(&patch, &backend)
        .await
        .expect_err("deleted edges must not generate a duplicated context candidate");

    assert!(
        error.message().contains("failed to find expected lines"),
        "{error}"
    );
    assert!(
        error
            .message()
            .contains("Recovery: read the target file again"),
        "{error}"
    );
    assert_eq!(backend.read("file.txt"), original);
}

#[tokio::test]
async fn duplicated_edge_candidate_rejects_added_edge_lines() {
    // anywork 本地差异：重复边缘候选仅限真实上下文行，新增边缘不能替代缺失的上下文配对。
    // 本地依据：code/pl-patch/src/apply.rs:267-271；对照 Codex file_update.rs:102-122。
    // Codex 只有原序列与尾空行缩短，没有重复边缘候选。
    for (case, body) in [
        (
            "leading_added_edge",
            "*** Update File: file.txt\n@@\n-edge\n+edge\n+inserted\n edge",
        ),
        (
            "trailing_added_edge",
            "*** Update File: file.txt\n@@\n edge\n-edge\n+inserted\n+edge",
        ),
    ] {
        let backend = TestBackend::new();
        let original = "edge\n";
        backend.write("file.txt", original);

        let error = apply_patch(&wrap_patch(body), &backend)
            .await
            .expect_err(case);

        assert!(
            error.message().contains("failed to find expected lines"),
            "{case}: {error}"
        );
        assert!(
            error
                .message()
                .contains("Recovery: read the target file again"),
            "{case}: {error}"
        );
        assert_eq!(backend.read("file.txt"), original, "{case}");
    }
}

#[tokio::test]
async fn duplicated_edge_context_preserves_file_whitespace() {
    // anywork 本地差异：合法重复边缘候选仍须保留命中上下文的缩进与尾随空白。
    // 本地映射依据：code/pl-patch/src/apply.rs:282-300；对照 Codex file_update.rs:102-122。
    // Codex 只有原序列与尾空行缩短，没有此候选。
    assert_update(
        "    edge  \n",
        "*** Update File: file.txt\n@@\n edge\n+inserted\n edge",
        "inserted\n    edge  \n",
    )
    .await;
}

#[tokio::test]
async fn duplicated_edge_context_preserves_json_property_value() {
    // anywork 本地差异：重复边缘候选命中时仍按上下文配对保留 JSON 原值与空白。
    // 本地依据：code/pl-patch/src/apply.rs:282-300、code/pl-patch/src/matching.rs:112-127。
    // Codex file_update.rs:102-122 只有原序列与尾空行缩短，没有此候选。
    let backend = TestBackend::new();
    backend.write("settings.json", "{\n    \"edge\": \"actual\"  \n}\n");

    backend
        .apply(
            "*** Update File: settings.json\n@@\n   \"edge\": \"expected\"\n+  \"inserted\": true,\n   \"edge\": \"expected\"",
        )
        .await;

    assert_eq!(
        backend.read("settings.json"),
        "{\n  \"inserted\": true,\n    \"edge\": \"actual\"  \n}\n"
    );
}
