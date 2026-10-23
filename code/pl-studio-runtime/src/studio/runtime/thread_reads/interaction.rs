use std::sync::Arc;

use pl_protocol::studio::{StudioError, TextChunk};
use pl_protocol::thread_facets::identity::ReadScopeIdentity;
use pl_protocol::thread_facets::read::interaction::{AnswerEntryPage, AnswerEntryReadItem,
    AnswerValuePage, AnswerValueReadItem, OptionPage, OptionReadItem, QuestionPage, QuestionReadItem};
use pl_protocol::{InteractionContent, InteractionRequest, UserInputAnswer, UserInputState};

use super::super::read_budget::{FieldTable, count, protocol, text_chunk};
use super::budget::{page, validate_revision};

mod fields;
mod header;

use fields::Field;

/// One already-validated canonical Interaction version. No source getter consults current state.
pub(super) struct InteractionMaterial {
    scope: ReadScopeIdentity,
    source: Arc<InteractionRequest>,
    fields: FieldTable<Field>,
    // Positions in the immutable HashMap's iteration order, sorted by the original question key.
    // This preserves unmatched historical keys without copying answer text or self-references.
    answer_order: Vec<usize>,
    // The original opaque tool arguments need one JSON-text projection, not a JSON schema tree.
    argument_json: Option<String>,
}

impl InteractionMaterial {
    pub(super) fn new(scope: ReadScopeIdentity, source: Arc<InteractionRequest>) -> Result<Self, StudioError> {
        validate_revision(&scope, source.revision)?;
        let mut answer_order = Vec::new();
        let argument_json = match &source.content {
            InteractionContent::UserInput(value) => {
                if let UserInputState::Resolved(resolved) = value.state() {
                    let mut keys: Vec<_> = resolved.answers().keys().enumerate().collect();
                    keys.sort_unstable_by(|(_, left), (_, right)| left.cmp(right));
                    answer_order = keys.into_iter().map(|(index, _)| index).collect();
                }
                None
            }
            InteractionContent::ToolApproval(value) => Some(serde_json::to_string(&value.request().arguments)
                .map_err(|_| protocol("Cannot serialize the original tool approval arguments"))?),
        };
        Ok(Self { scope, source, fields: FieldTable::default(), answer_order, argument_json })
    }

    pub(super) fn questions(&self, offset: u64, limit: u32) -> Result<QuestionPage, StudioError> {
        let questions = self.questions_source()?;
        let result = page(&self.scope, questions.len(), offset, limit, |index, inline| {
            let question = &questions[index];
            Ok(QuestionReadItem {
                index: count(index)?,
                id: self.read(Field::QuestionId(index), inline)?,
                header: self.read(Field::QuestionHeader(index), inline)?,
                question: self.read(Field::QuestionText(index), inline)?,
                is_other: question.is_other,
                is_secret: question.is_secret,
                options_count: question.options.as_ref().map(|options| count(options.len())).transpose()?,
            })
        })?;
        Ok(QuestionPage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    pub(super) fn options(&self, question_index: u64, offset: u64, limit: u32) -> Result<OptionPage, StudioError> {
        let question_index = usize::try_from(question_index).map_err(|_|
            StudioError::invalid_argument("Question index exceeds the pinned question list"))?;
        let options = self.questions_source()?.get(question_index)
            .and_then(|question| question.options.as_ref())
            .ok_or_else(|| StudioError::invalid_argument("The pinned question has no options list"))?;
        let result = page(&self.scope, options.len(), offset, limit, |index, inline| {
            Ok(OptionReadItem {
                index: count(index)?,
                label: self.read(Field::OptionLabel(question_index, index), inline)?,
                description: self.read(Field::OptionDescription(question_index, index), inline)?,
            })
        })?;
        Ok(OptionPage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    pub(super) fn answer_entries(&self, offset: u64, limit: u32) -> Result<AnswerEntryPage, StudioError> {
        self.answers_source()?;
        let result = page(&self.scope, self.answer_order.len(), offset, limit, |index, inline| {
            let (_, answer) = self.answer(index)?;
            Ok(AnswerEntryReadItem { index: count(index)?,
                question_id: self.read(Field::AnswerKey(index), inline)?,
                answer_count: count(answer.answers.len())? })
        })?;
        Ok(AnswerEntryPage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    pub(super) fn answer_values(&self, entry_index: u64, offset: u64, limit: u32) -> Result<AnswerValuePage, StudioError> {
        let entry_index = usize::try_from(entry_index).map_err(|_|
            StudioError::invalid_argument("Answer index exceeds the pinned answer list"))?;
        let (_, answer) = self.answer(entry_index)?;
        let result = page(&self.scope, answer.answers.len(), offset, limit, |index, inline| {
            Ok(AnswerValueReadItem { index: count(index)?,
                value: self.read(Field::AnswerValue(entry_index, index), inline)? })
        })?;
        Ok(AnswerValuePage { scope: result.scope, offset: result.offset, total: result.total,
            items: result.items, next_offset: result.next_offset })
    }

    pub(super) fn text(&self, field_id: u64, offset: u64, max_bytes: u32) -> Result<TextChunk, StudioError> {
        let field = self.fields.field(field_id)?;
        text_chunk(field_id, self.source_text(field)?, offset, max_bytes)
    }

    fn questions_source(&self) -> Result<&[pl_protocol::UserQuestion], StudioError> {
        match &self.source.content {
            InteractionContent::UserInput(value) => Ok(value.questions()),
            InteractionContent::ToolApproval(_) => Err(StudioError::invalid_argument(
                "Tool approval has no user-input question pages")),
        }
    }

    fn answers_source(&self) -> Result<&std::collections::HashMap<String, UserInputAnswer>, StudioError> {
        match &self.source.content {
            InteractionContent::UserInput(value) => match value.state() {
                UserInputState::Resolved(value) => Ok(value.answers()),
                UserInputState::Pending(_) | UserInputState::Cancelled(_) | UserInputState::Expired(_) =>
                    Err(StudioError::invalid_argument("The pinned interaction has no resolved user-input answers")),
            },
            InteractionContent::ToolApproval(_) => Err(StudioError::invalid_argument(
                "Tool approval has no user-input answer pages")),
        }
    }

    fn answer(&self, index: usize) -> Result<(&str, &UserInputAnswer), StudioError> {
        let original = self.answer_order.get(index).ok_or_else(||
            StudioError::invalid_argument("Answer index exceeds the pinned answer list"))?;
        self.answers_source()?.iter().nth(*original).map(|(key, value)| (key.as_str(), value))
            .ok_or_else(|| protocol("Pinned answer index no longer addresses its immutable source"))
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use pl_protocol::studio::{ReadText, StudioErrorCode};
    use pl_protocol::thread_facets::read::interaction::{InteractionReadContent, InteractionReadState};
    use pl_protocol::{InteractionCommand, InteractionContinuationPreset, InteractionPurpose,
        InteractionScope, MessagePresentation, ResolveUserInput, UserQuestion, UserQuestionOption};

    fn scope(revision: u64) -> ReadScopeIdentity {
        ReadScopeIdentity { scope_id: "thread-read-test".into(), runtime_epoch: "epoch-test".into(),
            incarnation: 1, source_revision: revision }
    }

    fn request(questions: Vec<UserQuestion>) -> InteractionRequest {
        InteractionRequest::user_input("interaction", InteractionScope { thread_id: "thread".into(),
            turn_id: "turn".into(), item_id: None, tool_id: None, agent_path: None,
            purpose: InteractionPurpose::General }, questions, 10)
    }

    fn question(id: &str, text: String) -> UserQuestion {
        UserQuestion { id: id.into(), header: "header".into(), question: text,
            is_other: false, is_secret: true, options: None }
    }

    #[test]
    fn typed_question_read_preserves_large_secret_text_and_nullable_options() {
        let original = "\0\\\"\n🙂".repeat(40_000);
        let mut with_options = question("choice", "choose".into());
        with_options.options = Some(vec![UserQuestionOption { label: "choice".into(), description: original.clone() }]);
        let mut empty_options = question("empty", String::new());
        empty_options.options = Some(Vec::new());
        let material = InteractionMaterial::new(scope(0), Arc::new(request(vec![
            question("large", original.clone()), with_options, empty_options,
        ]))).expect("pin canonical question source");
        let header = material.header().expect("typed header");
        assert_eq!(header.scope, scope(0));
        assert_eq!(header.content, InteractionReadContent::UserInput { question_count: 3 });
        let page = material.questions(0, 32).expect("question page");
        assert_eq!((page.total, page.next_offset), (3, None));
        assert!(page.items[0].is_secret);
        assert_eq!(page.items[0].options_count, None);
        assert_eq!(page.items[1].options_count, Some(1));
        assert_eq!(page.items[2].options_count, Some(0));
        let ReadText::Deferred { field_id, utf8_bytes } = &page.items[0].question else { panic!("large field must be deferred"); };
        let (field_id, utf8_bytes) = (*field_id, *utf8_bytes);
        assert_eq!(utf8_bytes, original.len() as u64);
        let mut offset = 0;
        let mut read = String::new();
        loop {
            let chunk = material.text(field_id, offset, 256 * 1024).expect("bounded UTF-8 chunk");
            assert_eq!(chunk.offset, offset);
            assert!(serde_json::to_vec(&chunk).expect("serialize text envelope").len() <= 256 * 1024);
            assert!(!chunk.text.is_empty());
            read.push_str(&chunk.text);
            match chunk.next_offset {
                Some(next) => { assert!(next > offset); offset = next; }
                None => break,
            }
        }
        assert_eq!(read, original);
        assert_eq!(material.text(field_id, 5, 4).expect_err("middle of a four-byte character").code, StudioErrorCode::InvalidArgument);
        assert_eq!(material.text(field_id, 0, 3).expect_err("insufficient text budget").code, StudioErrorCode::InvalidArgument);
        let end = material.text(field_id, utf8_bytes, 4).expect("end-of-text is a valid empty chunk");
        assert_eq!((end.text, end.next_offset), (String::new(), None));
        let options = material.options(1, 0, 32).expect("nested option page");
        assert_eq!(options.total, 1);
        assert!(matches!(&options.items[0].description, ReadText::Deferred { utf8_bytes: bytes, .. } if *bytes == utf8_bytes));
        assert!(material.questions(3, 32).expect("end page").items.is_empty());
        assert_eq!(material.questions(4, 32).expect_err("out-of-range offset").code, StudioErrorCode::InvalidArgument);
    }

    #[test]
    fn escaped_header_and_page_budgets_defer_or_stop_without_truncating_fields() {
        let escaped = "\0".repeat(4096);
        let questions = (0..100).map(|index| UserQuestion { id: index.to_string(),
            header: escaped.clone(), question: escaped.clone(), is_other: false, is_secret: false,
            options: None }).collect();
        let mut source = InteractionRequest::user_input(escaped.clone(), InteractionScope {
            thread_id: escaped.clone(), turn_id: escaped.clone(), item_id: Some(escaped.clone()),
            tool_id: Some(escaped.clone()), agent_path: Some(escaped.clone()),
            purpose: InteractionPurpose::AgentSessionPlanConfirmation(
            pl_protocol::AgentSessionPlanConfirmationPurpose { expected_revision: 7,
                    operation_id: escaped.clone(), argument_hash: escaped.clone(), plan_hash: escaped.clone() }),
        }, questions, 10);
        source.continuation = Some(InteractionContinuationPreset::question(escaped.clone(), MessagePresentation::Hidden));
        let material = InteractionMaterial::new(scope(0), Arc::new(source)).expect("pin escaped source");
        let header = material.header().expect("header must defer small aggregate fields");
        assert!(serde_json::to_vec(&header).expect("serialize header").len() <= 256 * 1024);
        assert!(matches!(header.interaction_id, ReadText::Deferred { utf8_bytes: 4096, .. }));
        let mut offset = 0;
        let mut ids = Vec::new();
        loop {
            let page = material.questions(offset, 100).expect("escaped question page");
            assert!(serde_json::to_vec(&page).expect("serialize complete page").len() <= 256 * 1024);
            assert!(!page.items.is_empty());
            assert!(page.items.len() < 100);
            for item in page.items {
                let ReadText::Inline { text } = item.id else { panic!("small numeric identity should be inline"); };
                ids.push(text);
                assert_eq!(item.question, ReadText::Inline { text: escaped.clone() });
            }
            match page.next_offset { Some(next) => { assert!(next > offset); offset = next; }, None => break }
        }
        assert_eq!(ids, (0..100).map(|index| index.to_string()).collect::<Vec<_>>());
    }

    #[test]
    fn resolved_answer_pages_keep_sorted_historical_keys_and_original_value_order() {
        let pending = Arc::new(request(vec![question("a", "question".into())]));
        let original = InteractionMaterial::new(scope(0), pending.clone()).expect("pin pending version");
        let mut resolved = (*pending).clone();
        let decision = resolved.decide(InteractionCommand::ResolveUserInput(ResolveUserInput {
            interaction_id: resolved.interaction_id.clone(), expected_revision: 0, operation_id: "resolve".into(), resolved_at: 11,
            answers: std::collections::HashMap::from([
                ("z-unmatched".into(), UserInputAnswer { answers: vec!["two".into(), "one".into()] }),
                ("a".into(), UserInputAnswer { answers: Vec::new() }),
            ]),
        })).expect("canonical resolution");
        resolved.apply(decision, 11);
        let resolved = Arc::new(resolved);
        let material = InteractionMaterial::new(scope(1), resolved.clone()).expect("pin resolved version");
        assert_eq!(original.header().expect("original immutable header").state,
            InteractionReadState::Pending { operation_id: ReadText::Inline { text: "interaction".into() } });
        let page = material.answer_entries(0, 32).expect("ordered answer keys");
        assert_eq!(page.items, vec![
            AnswerEntryReadItem { index: 0, question_id: ReadText::Inline { text: "a".into() }, answer_count: 0 },
            AnswerEntryReadItem { index: 1, question_id: ReadText::Inline { text: "z-unmatched".into() }, answer_count: 2 },
        ]);
        assert!(material.answer_values(0, 0, 32).expect("empty answer list").items.is_empty());
        assert_eq!(material.answer_values(1, 0, 32).expect("original answer order").items, vec![
            AnswerValueReadItem { index: 0, value: ReadText::Inline { text: "two".into() } },
            AnswerValueReadItem { index: 1, value: ReadText::Inline { text: "one".into() } },
        ]);
        assert_eq!(InteractionMaterial::new(scope(0), resolved).err().expect("old revision must not read latest").code,
            StudioErrorCode::Superseded);
    }
}
