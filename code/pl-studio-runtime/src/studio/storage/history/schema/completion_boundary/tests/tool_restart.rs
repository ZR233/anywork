use super::*;
use crate::studio::{
    storage::{
        history::{EffectCommit, HistoryStore},
        thread_writer::HistoryChannel,
    },
    thread_projection::LiveProjection,
};
use pl_core::{
    chat::{ChatHistory, ContentReadRequest, TimelineEpoch},
    context::{ContextRecord, ContextSnapshot, ContextSource},
    model::ModelToolCall,
    thread::{ThreadHandle, ToolOutcome},
};

#[tokio::test]
async fn archived_tool_arguments_allow_actual_core_recovery_terminal_to_commit() -> Result<()> {
    eprintln!("tool recovery: creating runtime fixture");
    let env = crate::runtime_test_support::Environment::new(vec![], vec![]).await?;
    eprintln!("tool recovery: runtime fixture ready");
    let result = async {
        let mut thread = pl_protocol::Thread::from(env.runtime.create_thread(
            &env.project.id, "migrated interrupted tool",
        ).await?);
        thread.id = THREAD.into();
        let path = env._temp.path().join("legacy-tool.sqlite");
        let db = connect(&path, crate::studio::paths::SqliteFileMode::Create).await?;
        Published16.up(&db, None).await?;
        let (database, _) = seed(&db).await?;
        let store = HistoryStore::open(&path, THREAD).await?;
        let arguments = format!("{{\"value\":\"{}\"}}", "工具参数".repeat(30_000));
        let id = crate::studio::thread_projection::order::tool_id("old-call");
        let item = ThreadItem::new(id.clone(),THREAD.into(),"tool-turn".into(),2,1,3,3,
            ThreadItemState::Tool(ThreadToolItem::new(
                ThreadToolInvocation::new("old-call".into(),"side_effect".into(),arguments.clone()),
                ThreadToolState::Running(RunningThreadTool::new(String::new())),
            )),
        );
        store.upsert_item(&db,3,item.clone()).await?;
        let old_key = ChatContentKey {
            owner: pl_core::chat::ChatKey::new("item",&id)?,
            key:"tool.arguments".into(),
        };
        super::super::super::legacy_content::write_content(&db,&ChatContent {
            descriptor: ContentDescriptor {key:old_key.clone(),byte_length:arguments.len() as u64,
                generation:7,media_type:None},
            data:ContentData::Bytes(Arc::from(arguments.clone().into_bytes())),
        },false).await?;
        let mut checkpoint = *checkpoint::read(&db,THREAD).await?.context("checkpoint")?;
        checkpoint.state.context = ContextSnapshot {revision:1,records:vec![ContextRecord {
            id:"call-record".into(),turn_id:Some("tool-turn".into()),source:ContextSource::Assistant,
            content:vec![],tool_calls:vec![ModelToolCall {
                call_id:"old-call".into(),tool_id:"side_effect".into(),
                arguments:OpaquePayload::new("tool.arguments",1,arguments.clone())?,
                presentation_contract:None,rejection:None,
            }],
        }].into()};
        checkpoint::write(&db,&checkpoint,None,None).await?;
        let before = originals(&db).await?;
        let original_manifest = rows(&db, "SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM conversation_contents WHERE content_key='tool.arguments'").await?;
        let original_chunks = rows(&db, "SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM conversation_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?;
        prepare(&db,THREAD,Preparation::Schema,None).await?;
        eprintln!("tool recovery: migration committed");
        assert_eq!(originals(&db).await?,before);
        assert_eq!(rows(&db,"SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM completion_boundary_archive_contents WHERE content_key='tool.arguments'").await?,original_manifest);
        assert_eq!(rows(&db,"SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM completion_boundary_archive_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?,original_chunks);
        assert!(rows(&db,"SELECT owner_key AS value FROM conversation_contents WHERE content_key='tool.arguments'").await?.is_empty());
        db.close().await?;

        // This is the real Core recovery reducer, not a hand-constructed terminal delivery.
        let owner = ThreadHandle::resume_without_model(THREAD.into(),Some(checkpoint))?;
        let mut settled = owner.snapshot();
        let effects = owner.effect_page(3,std::num::NonZeroUsize::new(32).unwrap()).await?;
        assert!(!effects.is_empty());
        let delivery = effects.iter().flat_map(|effect| effect.deliveries.iter())
            .find(|delivery| delivery.call_id=="old-call").context("Core recovery delivery")?;
        assert!(matches!(delivery.outcome,ToolOutcome::Interrupted));
        let channel=HistoryChannel::new(Arc::new(std::sync::atomic::AtomicU64::new(0)));
        let chat=pl_core::chat::Session::new(store.clone(),TimelineEpoch::new("tool-recovery")?);
        let mut projection=LiveProjection::new();
        projection.bind_execution_history(channel.order_index(),store.clone())?;
        projection.bind_conversation_identity(database.clone())?;
        projection.seed(vec![item],Default::default());
        projection.restore_current(&chat,&thread,&settled).await?;
        eprintln!("tool recovery: current restored");
        for effect in &effects {
            // Reattach the original effect's transfer facts, which live snapshots prune.
            settled.deliveries = effect.deliveries.clone();
            let (_,mut prepared)=projection.prepare(&thread,effect,&settled,false).await?;
            projection.publish_prepared(&chat,&mut prepared).await?;
            store.commit_effect(effect.sequence,EffectCommit {
                items:&prepared.items,completions:&prepared.completions,current:&prepared.current,
                rolled_back_turns:&Default::default(),identities:&[],messages:&[],receipts:&[],
                tasks:&[],deliveries:&[],delivery_repairs:&[],attempt:effect.attempt.as_ref(),
            }).await?;
        }
        assert!(store.watermark().await?>3);
        let saved=store.read_chat_item(&id).await?.context("completed interrupted tool")?;
        let body=saved.contents.get(&old_key).context("full arguments")?;
        assert_eq!(body.data.range(0,arguments.len())?.as_bytes(),arguments.as_bytes());
        owner.close().await?;
        drop(projection);
        drop(chat);
        store.close_for_deletion().await?;
        eprintln!("tool recovery: history closed");
        let store=HistoryStore::open(&path,THREAD).await?;
        let mut recovered = Vec::new();
        while recovered.len() < arguments.len() {
            let body=ChatHistory::read_content(&store,&ContentReadRequest {
                epoch:TimelineEpoch::new("cold-tool")?,
                reference:pl_core::chat::ContentRef::Body(old_key.clone()),
                offset:recovered.len() as u64,max_bytes:64*1024,generation:None,
            }).await?;
            assert!(body.sealed);
            assert!(!body.bytes.as_bytes().is_empty());
            recovered.extend_from_slice(body.bytes.as_bytes());
        }
        assert_eq!(recovered,arguments.as_bytes());
        {
            let connection = store.writer().await?;
            let db = &connection.db;
            assert_eq!(rows(db,"SELECT json_array(owner_key,content_key,hex(payload)) AS value FROM completion_boundary_archive_contents WHERE content_key='tool.arguments'").await?,original_manifest);
            assert_eq!(rows(db,"SELECT json_array(owner_key,content_key,byte_offset,hex(data)) AS value FROM completion_boundary_archive_content_chunks WHERE content_key='tool.arguments' ORDER BY byte_offset").await?,original_chunks);
            assert_eq!(originals(db).await?[0][0],before[0][0],"unrelated completed A is unchanged");
        }
        store.close_for_deletion().await?;
        Ok::<_,anyhow::Error>(())
    }.await;
    eprintln!("tool recovery: result before runtime shutdown: {result:?}");
    env.finish(result).await
}
