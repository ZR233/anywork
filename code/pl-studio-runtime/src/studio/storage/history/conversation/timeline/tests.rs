use super::*;
use pl_protocol::*;
use sea_orm::TransactionTrait;

fn at(effect:u64)->ChatFactPosition { ChatFactPosition{effect_seq:effect,suborder:0} }
fn active(id:&str,kind:ChatAtomKind,effect:u64)->ChatAtom {
    ChatAtom { id:id.into(),completion_item_id:None,completion_seq:None,
        source:ChatSourceId::ForegroundTurn{turn_id:"turn".into()},source_state:None,source_order:Some(effect),
        kind,delivery:ChatDeliveryKind::Foreground,lifecycle:ChatAtomLifecycle::Active{started:Some(at(effect)),status:ChatActiveStatus::Running},
        turn_id:Some("turn".into()),attempt_id:None,tool:None,wait:None,text_channel:None,started_at:Some(effect as i64),finished_at:None,
        content_present:None,contents:Vec::new(),payload:None }
}
async fn persist(db:&impl ConnectionTrait,projection:&mut TimelineProjection,effect:u64)->Result<()> {
    projection.commit_ready()?;
    let committed=projection.take_committed().into_iter().map(|item|PreparedTimelineItem{item}).collect::<Vec<_>>();
    let update=projection.take_update()?;
    save_update(db,"db",&update,&committed,effect,true).await?;
    let mut current=CurrentProjection::empty(effect,ThreadStatus::Idle);
    current.items=projection.current_items();
    db.execute_raw(statement("UPDATE history_meta SET applied_write_seq=? WHERE id=1",vec![integer(effect)?.into()])).await?;
    db.execute_raw(statement("INSERT INTO conversation_view_state(singleton_id,payload) VALUES(1,?) ON CONFLICT(singleton_id) DO UPDATE SET payload=excluded.payload",vec![serde_json::to_vec(&current)?.into()])).await?;
    Ok(())
}

#[tokio::test]
async fn text_start_commits_group_without_new_atom_and_source_facts_rebuild_the_same_cut()->Result<()> {
    let (_directory,db)=super::super::tests::fixture().await?;
    db.execute_unprepared(CREATE_SCHEMA).await?;
    let mut projection=TimelineProjection::new("db".into(),0);
    let work=active("z",ChatAtomKind::Reasoning,1);
    projection.observe(&work,None)?;
    persist(&db,&mut projection,1).await?;
    assert!(page_rows(&db,&ChatScope::Main,None,100,1,1).await?.is_empty());
    let reference=projection.current_items()[0].members.clone().unwrap();
    let mut terminal=work.clone();
    terminal.lifecycle=ChatAtomLifecycle::Terminal{started:Some(at(1)),ended:Some(at(2)),outcome:ChatTerminalOutcome::Completed};
    terminal.completion_item_id=Some("original-completion".into());terminal.completion_seq=Some(1);terminal.finished_at=Some(2);
    // A deliberately opaque, malformed body proves folded Main and rebuild do
    // not need a JSON/payload decoder. The original bytes remain untouched.
    db.execute_raw(statement("INSERT INTO conversation_items(seq,item_id,query_class,parent_id,payload,metadata) VALUES(1,'original-completion','conversation',NULL,?,?)",vec![b"opaque original body".to_vec().into(),serde_json::to_vec(&terminal)?.into()])).await?;
    projection.complete(terminal,1,Some(PayloadData::Deferred{reference:ContentRef{database_id:"db".into(),target:ContentTarget::ItemPayload{item_id:"original-completion".into()}},byte_length:20}))?;
    persist(&db,&mut projection,2).await?;
    assert!(page_rows(&db,&ChatScope::Main,None,100,2,1).await?.is_empty());
    projection.observe(&active("text",ChatAtomKind::Text,3),None)?;
    persist(&db,&mut projection,3).await?;
    let before=page_rows(&db,&ChatScope::Main,None,100,3,1).await?;
    assert_eq!(before.len(),1);
    let ChatEntry::Item(item)=&before[0].1 else{panic!("Main returned a member");};
    assert_eq!(item.kind,TimelineItemKind::WorkGroup);
    assert_eq!(item.summary.as_ref().unwrap().member_count,1);
    assert!(item.payload.is_none());assert_eq!(item.outcome,None);
    let members=page_rows(&db,&ChatScope::GroupMembers{reference:reference.clone()},None,100,3,1).await?;
    assert!(matches!(&members[0].1,ChatEntry::Atom(atom) if atom.completion_item_id.as_deref()==Some("original-completion") && matches!(atom.payload,Some(PayloadData::Deferred{..}))));
    let mut wrong=reference.clone();wrong.database_id="another".into();
    assert!(validate_members_ref(&db,"db",&wrong).await.is_err());
    wrong=reference;wrong.projection_version+=1;
    assert!(validate_members_ref(&db,"db",&wrong).await.is_err());
    let tx=db.begin().await?;
    tx.execute_unprepared("DELETE FROM timeline_items;DELETE FROM timeline_item_members;DELETE FROM timeline_projection_state;").await?;
    rebuild(&tx,"db").await?;tx.commit().await?;
    assert_eq!(before,page_rows(&db,&ChatScope::Main,None,100,3,1).await?);
    let mut restored=TimelineProjection::new("db".into(),next_position(&db).await?);
    restored.restore_recovery(&recovery(&db).await?)?;
    assert_eq!(restored.current_items(),projection.current_items());
    let bytes:Vec<u8>=db.query_one_raw(statement("SELECT payload FROM conversation_items WHERE seq=1",vec![])).await?.unwrap().try_get("","payload")?;
    assert_eq!(bytes,b"opaque original body");
    // An actual failed replacement transaction retains the complete old index,
    // not merely a use_transaction declaration.
    let tx=db.begin().await?;
    tx.execute_unprepared("CREATE TRIGGER reject_timeline_rebuild BEFORE INSERT ON timeline_items BEGIN SELECT RAISE(ABORT,'injected rebuild failure'); END;").await?;
    assert!(rebuild(&tx,"db").await.is_err());tx.rollback().await?;
    assert_eq!(before,page_rows(&db,&ChatScope::Main,None,100,3,1).await?);
    Ok(())
}
