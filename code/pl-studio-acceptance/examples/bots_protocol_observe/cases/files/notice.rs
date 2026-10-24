//! Deterministic recognition of the product's complete delivery notification.
//! This is not a natural-language classifier or Markdown parser: a notice must
//! match one complete affirmative template with the actual filename exactly.

pub(super) fn is_delivery_notice(text: &str, filename: &str) -> bool {
    if filename.is_empty() {
        return false;
    }
    let Some((before, after)) = text.split_once(filename) else {
        return false;
    };
    if after.contains(filename) {
        return false;
    }
    let before = neutral_layout(before);
    let after = neutral_layout(after);
    const TEMPLATES: &[(&str, &str)] = &[
        (
            "正文超过飞书富文本大小限制，完整 Markdown 原文已作为 UTF-8 文件 ",
            " 交付，可下载查看。",
        ),
        (
            "完整 Markdown 原文已作为 UTF-8 文件 ",
            " 交付，可下载查看。",
        ),
        ("完整 Markdown 原文已交付为文件 ", "，可下载查看。"),
        (
            "The complete Markdown original has been delivered as UTF-8 file ",
            "; download it to view.",
        ),
    ];
    TEMPLATES.iter().any(|(prefix, suffix)| {
        let prefix = neutral_layout(prefix);
        let suffix = neutral_layout(suffix);
        (before == prefix && after == suffix)
            || (before == format!("{prefix}`") && after == format!("`{suffix}"))
    })
}

/// Whitespace and statement separators do not change these finite templates.
/// Filename bytes are excluded from this normalization. Question marks, quotes,
/// arbitrary clauses and Markdown fences are not ignored.
fn neutral_layout(text: &str) -> String {
    text.chars()
        .filter(|character| {
            !character.is_whitespace() && !matches!(character, ',' | '，' | '.' | '。' | ';' | '；')
        })
        .collect()
}
