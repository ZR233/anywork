use pl_output::OutputExcerpt;

#[test]
fn project_keeps_byte_budget_original_length_and_single_omission() {
    for (head, tail, gap) in [
        (
            "汉字边界".as_bytes()[..4].to_vec(),
            "汉字边界".as_bytes()[4..].to_vec(),
            0,
        ),
        (b"head".repeat(1000), b"tail".repeat(1000), 1_000_000),
        (vec![0xff, 0xfe, b'a'], vec![0xff, b'z'], 100),
    ] {
        let raw_length = head.len() + tail.len() + gap;
        let excerpt = OutputExcerpt::from_parts(head, tail, gap);
        for cap in 0..=128 {
            let visible = excerpt.clone().project(cap);
            assert!(visible.content.len() <= cap);
            assert_eq!(visible.original_length, raw_length);
            assert!(visible.content.matches("[output omitted]").count() <= 1);
        }
    }
}
