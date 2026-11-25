use super::*;

#[test]
fn a_removed_or_replaced_field_never_revalidates_an_old_reference() -> Result<()> {
    let mut owner = StateResources::default();
    owner.bind("run-1".into());
    let original = "原始详情".repeat(600);
    let mut value = Some(original.clone());
    let mut heads = Vec::new();
    owner.defer("state:runtime", "progress", &mut value, &mut heads)?;
    let CurrentStateField::Body {
        reference: first, ..
    } = heads.pop().unwrap()
    else {
        panic!("body field");
    };
    assert!(value.is_none());
    assert_eq!(
        serde_json::from_slice::<String>(&owner.body(&first).unwrap())?,
        original
    );

    let mut small = Some("changed to a small inline value".to_owned());
    owner.defer("state:runtime", "progress", &mut small, &mut heads)?;
    assert!(heads.is_empty());
    assert!(small.is_some());
    assert!(owner.body(&first).is_none());

    let mut returned = Some(original);
    owner.defer("state:runtime", "progress", &mut returned, &mut heads)?;
    let CurrentStateField::Body {
        reference: successor,
        ..
    } = heads.pop().unwrap()
    else {
        panic!("body field");
    };
    assert_ne!(successor.generation, first.generation);
    assert!(owner.body(&first).is_none());
    owner.bind("run-2".into());
    assert!(owner.body(&successor).is_none());
    Ok(())
}

#[test]
fn large_state_lists_page_with_exact_counts_and_retire_all_old_continuations() -> Result<()> {
    let mut owner = StateResources::default();
    owner.bind("run-1".into());
    let original: Vec<String> = (0..301)
        .map(|i| format!("skill-{i}:{}", "正文".repeat(300)))
        .collect();
    let mut values = original.clone();
    let mut heads = Vec::new();
    owner.defer_collection("state:runtime", "activeSkills", &mut values, &mut heads)?;
    let CurrentStateField::Collection {
        reference, count, ..
    } = heads.pop().unwrap()
    else {
        panic!("collection");
    };
    assert_eq!(count, original.len() as u64);
    assert!(values.is_empty());
    assert!(serde_json::to_vec(&reference)?.len() < 256);
    let demand = ReadDemand {
        max_items: 7,
        max_bytes: 2048,
    };
    let mut after = None;
    let mut actual = Vec::new();
    loop {
        let page = owner
            .page(&reference, after.as_deref(), demand, Ok)?
            .unwrap();
        assert!(serde_json::to_vec(&page)?.len() <= demand.max_bytes as usize);
        assert!(page.entries.len() <= demand.max_items as usize);
        for entry in page.entries {
            let bytes = match entry.payload {
                crate::CurrentPayloadData::Inline { bytes } => bytes,
                crate::CurrentPayloadData::Deferred { reference, .. } => {
                    owner.body(&reference).unwrap().to_vec()
                }
            };
            actual.push(serde_json::from_slice::<String>(&bytes)?);
        }
        let Some(next) = page.continuation else {
            break;
        };
        after = Some(next);
    }
    assert_eq!(actual, original);

    let mut same = original.clone();
    owner.defer_collection("state:runtime", "activeSkills", &mut same, &mut heads)?;
    let CurrentStateField::Collection {
        reference: same, ..
    } = heads.pop().unwrap()
    else {
        panic!("collection");
    };
    assert_eq!(same, reference);
    let mut changed = original;
    changed[0].push_str("changed");
    owner.defer_collection("state:runtime", "activeSkills", &mut changed, &mut heads)?;
    assert!(owner.page(&reference, None, demand, Ok)?.is_none());

    let mut saved = StateResources::cold("run-1".into(), 0);
    let mut values = actual;
    saved.defer_collection("state:runtime", "activeSkills", &mut values, &mut heads)?;
    let CurrentStateField::Collection {
        reference: cold, ..
    } = heads.pop().unwrap()
    else {
        panic!("collection");
    };
    assert_ne!(
        cold.revision, reference.revision,
        "saved and live refs cannot alias under the same source run"
    );
    assert!(saved.page(&reference, None, demand, Ok)?.is_none());
    Ok(())
}
