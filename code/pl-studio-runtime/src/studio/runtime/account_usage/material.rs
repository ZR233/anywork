use super::super::models::page_budget::{PageBinding, page};
use super::super::read_budget::{FieldTable, bounded_header, count, text_chunk};
use super::source::UsageMaterial;
use crate::{AccountUsageData, AccountUsageState, ZhipuQuotaWindow};
use pl_protocol::ObservedResource;
use pl_protocol::products::identity::ProductEntityRef;
use pl_protocol::products::read::account_usage::*;
use pl_protocol::products::read::primitives::TypedListRef;
use pl_protocol::products::source::{ProductSourceStatusReadHeader, SourceStateErrorRead};
use pl_protocol::studio::{ReadText, StudioError, StudioErrorCode, TextChunk};
use std::sync::Arc;

#[derive(Clone, Copy, PartialEq, Eq)]
enum Text {
    Fingerprint,
    Account(usize),
    Operation(usize),
    Message(usize),
    ErrorCode(usize),
    ErrorMessage(usize),
    Level(usize),
    Balance(usize, usize, u8),
    Window(usize, usize),
    Detail(usize, usize, usize),
    SourceOperation,
    SourceCode,
    SourceMessage,
}
#[derive(Clone, Copy, PartialEq, Eq)]
enum List {
    Usages,
    Balances(usize),
    Limits(usize),
    Details(usize, usize),
}
pub(super) struct UsageReadMaterial {
    pub source: Arc<UsageMaterial>,
    texts: FieldTable<Text>,
    lists: FieldTable<List>,
}
impl UsageReadMaterial {
    pub fn new(source: Arc<UsageMaterial>) -> Self {
        Self {
            source,
            texts: FieldTable::default(),
            lists: FieldTable::default(),
        }
    }
    fn data(&self) -> Result<&super::AccountUsageStateData, StudioError> {
        self.source.value.state.value().ok_or_else(wrong)
    }
    fn usage(&self, index: usize) -> Result<&crate::AccountUsageRecord, StudioError> {
        self.data()?.usages.get(index).ok_or_else(wrong)
    }
    fn usage_data(&self, index: usize) -> Result<&AccountUsageData, StudioError> {
        match self.usage(index)?.state() {
            AccountUsageState::Ready(value) => Ok(value.data()),
            _ => Err(wrong()),
        }
    }
    fn balances_value(&self, index: usize) -> Result<&crate::DeepSeekBalanceUsage, StudioError> {
        match self.usage_data(index)? {
            AccountUsageData::DeepSeekBalance(value) => Ok(value),
            _ => Err(wrong()),
        }
    }
    fn quota(&self, index: usize) -> Result<&crate::ZhipuCodingPlanUsage, StudioError> {
        match self.usage_data(index)? {
            AccountUsageData::ZhipuCodingPlan(value) => Ok(value),
            _ => Err(wrong()),
        }
    }
    fn list(&self, field: List, len: usize) -> Result<TypedListRef, StudioError> {
        Ok(TypedListRef {
            list_id: self.lists.register(field)?,
            total: count(len)?,
        })
    }
    fn read(&self, field: Text, inline: usize) -> Result<ReadText, StudioError> {
        self.texts.read(field, self.text_source(field)?, inline)
    }
    pub fn header(&self) -> Result<AccountUsageReadHeader, StudioError> {
        bounded_header(|inline| {
            Ok(AccountUsageReadHeader {
                config_fingerprint: self.read(Text::Fingerprint, inline)?,
                usages: self.list(List::Usages, self.data()?.usages.len())?,
            })
        })
    }
    fn usage_read(&self, index: usize, inline: usize) -> Result<AccountUsageRead, StudioError> {
        let value = self.usage(index)?;
        let state = match value.state() {
            AccountUsageState::Unsupported(_) => AccountUsageResultRead::Unsupported,
            AccountUsageState::MissingCredential(_) => AccountUsageResultRead::MissingCredential {
                message: self.read(Text::Message(index), inline)?,
            },
            AccountUsageState::Failed(value) => AccountUsageResultRead::Failed {
                error: SourceStateErrorRead {
                    code: self.read(Text::ErrorCode(index), inline)?,
                    message: self.read(Text::ErrorMessage(index), inline)?,
                    retryable: value.error().retryable,
                },
            },
            AccountUsageState::Ready(value) => AccountUsageResultRead::Ready {
                data: match value.data() {
                    AccountUsageData::DeepSeekBalance(value) => {
                        AccountUsageDataRead::DeepSeekBalance {
                            is_available: value.is_available,
                            balances: self.list(List::Balances(index), value.balances.len())?,
                        }
                    }
                    AccountUsageData::ZhipuCodingPlan(value) => {
                        AccountUsageDataRead::ZhipuCodingPlan {
                            level: value
                                .level
                                .as_ref()
                                .map(|_| self.read(Text::Level(index), inline))
                                .transpose()?,
                            limits: self.list(List::Limits(index), value.limits.len())?,
                        }
                    }
                },
            },
        };
        Ok(AccountUsageRead {
            account_id: self.read(Text::Account(index), inline)?,
            revision: value.revision(),
            updated_at: value.updated_at(),
            last_operation_id: self.read(Text::Operation(index), inline)?,
            state,
        })
    }
    pub fn entries(&self, offset: u64, limit: u32) -> Result<AccountUsageEntryPage, StudioError> {
        let collection = self.source.collection.ok_or_else(wrong)?;
        let result = page(
            PageBinding::Collection(collection),
            self.source.entities.len(),
            offset,
            limit,
            |index, _| Ok(self.source.entities[index]),
        )?;
        Ok(AccountUsageEntryPage {
            collection,
            offset,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn entity(
        &self,
        reference: ProductEntityRef,
    ) -> Result<AccountUsageEntityRead, StudioError> {
        let index = self
            .source
            .entities
            .iter()
            .position(|item| item.entry == reference.entry)
            .ok_or_else(|| StudioError::not_found("Usage member"))?;
        if self.source.entities[index] != reference {
            return Err(StudioError::new(
                StudioErrorCode::Superseded,
                "Usage entity revision does not belong to this scope",
                false,
            ));
        }
        bounded_header(|inline| {
            Ok(AccountUsageEntityRead {
                reference,
                value: self.usage_read(index, inline)?,
            })
        })
    }
    pub fn lookup(&self, account: &str) -> Result<Option<ProductEntityRef>, StudioError> {
        Ok(self
            .data()?
            .usages
            .iter()
            .position(|item| item.account_id() == account)
            .map(|index| self.source.entities[index]))
    }
    pub fn usages(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<AccountUsageReadPage, StudioError> {
        if self.lists.field(list_id)? != List::Usages {
            return Err(wrong());
        }
        let result = page(
            PageBinding::List(list_id),
            self.data()?.usages.len(),
            offset,
            limit,
            |index, inline| self.usage_read(index, inline),
        )?;
        Ok(AccountUsageReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn balances(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<BalanceReadPage, StudioError> {
        let List::Balances(account) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let result = page(
            PageBinding::List(list_id),
            self.balances_value(account)?.balances.len(),
            offset,
            limit,
            |index, inline| {
                let text = |field| self.read(Text::Balance(account, index, field), inline);
                Ok(BalanceRead {
                    currency: text(0)?,
                    total_balance: text(1)?,
                    granted_balance: text(2)?,
                    topped_up_balance: text(3)?,
                })
            },
        )?;
        Ok(BalanceReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn quota_limits(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<QuotaLimitReadPage, StudioError> {
        let List::Limits(account) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let result = page(
            PageBinding::List(list_id),
            self.quota(account)?.limits.len(),
            offset,
            limit,
            |index, inline| {
                let value = &self.quota(account)?.limits[index];
                let window = match &value.window {
                    ZhipuQuotaWindow::FiveHour => QuotaWindowRead::FiveHour,
                    ZhipuQuotaWindow::Weekly => QuotaWindowRead::Weekly,
                    ZhipuQuotaWindow::McpMonthly => QuotaWindowRead::McpMonthly,
                    ZhipuQuotaWindow::Other(_) => {
                        QuotaWindowRead::Other(self.read(Text::Window(account, index), inline)?)
                    }
                };
                Ok(QuotaLimitRead {
                    window,
                    percentage: value.percentage,
                    current_value: value.current_value,
                    total: value.total,
                    remaining: value.remaining,
                    next_reset_at: value.next_reset_at,
                    usage_details: self
                        .list(List::Details(account, index), value.usage_details.len())?,
                })
            },
        )?;
        Ok(QuotaLimitReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn quota_details(
        &self,
        list_id: u64,
        offset: u64,
        limit: u32,
    ) -> Result<QuotaDetailReadPage, StudioError> {
        let List::Details(account, window) = self.lists.field(list_id)? else {
            return Err(wrong());
        };
        let details = &self
            .quota(account)?
            .limits
            .get(window)
            .ok_or_else(wrong)?
            .usage_details;
        let result = page(
            PageBinding::List(list_id),
            details.len(),
            offset,
            limit,
            |index, inline| {
                let value = &details[index];
                Ok(QuotaDetailRead {
                    name: self.read(Text::Detail(account, window, index), inline)?,
                    current_value: value.current_value,
                    total: value.total,
                    percentage: value.percentage,
                })
            },
        )?;
        Ok(QuotaDetailReadPage {
            list_id,
            offset,
            total: result.total,
            items: result.items,
            next_offset: result.next_offset,
        })
    }
    pub fn status_header(&self) -> Result<ProductSourceStatusReadHeader, StudioError> {
        bounded_header(|inline| {
            let error = |retryable| -> Result<_, StudioError> {
                Ok(SourceStateErrorRead {
                    code: self.read(Text::SourceCode, inline)?,
                    message: self.read(Text::SourceMessage, inline)?,
                    retryable,
                })
            };
            Ok(match &self.source.value.state {
                ObservedResource::Uninitialized(value) => {
                    ProductSourceStatusReadHeader::Uninitialized {
                        revision: value.revision(),
                        updated_at: value.updated_at(),
                    }
                }
                ObservedResource::Loading(value) => ProductSourceStatusReadHeader::Loading {
                    revision: value.revision(),
                    operation: value.operation(),
                    operation_id: self.read(Text::SourceOperation, inline)?,
                    started_at: value.started_at(),
                },
                ObservedResource::Ready(value) => ProductSourceStatusReadHeader::Ready {
                    revision: value.revision(),
                    updated_at: value.updated_at(),
                    last_checked_at: value.last_checked_at(),
                },
                ObservedResource::Refreshing(value) => ProductSourceStatusReadHeader::Refreshing {
                    revision: value.revision(),
                    operation: value.operation(),
                    operation_id: self.read(Text::SourceOperation, inline)?,
                    started_at: value.started_at(),
                    last_checked_at: value.last_checked_at(),
                },
                ObservedResource::Stale(value) => ProductSourceStatusReadHeader::Stale {
                    revision: value.revision(),
                    stale_at: value.stale_at(),
                    last_checked_at: value.last_checked_at(),
                },
                ObservedResource::Degraded(value) => ProductSourceStatusReadHeader::Degraded {
                    revision: value.revision(),
                    failed_at: value.failed_at(),
                    last_checked_at: value.last_checked_at(),
                    operation: value.operation(),
                    error: error(value.error().retryable)?,
                },
                ObservedResource::Failed(value) => ProductSourceStatusReadHeader::Failed {
                    revision: value.revision(),
                    failed_at: value.failed_at(),
                    operation: value.operation(),
                    error: error(value.error().retryable)?,
                },
                ObservedResource::Stopped(value) => ProductSourceStatusReadHeader::Stopped {
                    revision: value.revision(),
                    stopped_at: value.stopped_at(),
                },
            })
        })
    }
    pub fn text(
        &self,
        field_id: u64,
        offset: u64,
        max_bytes: u32,
    ) -> Result<TextChunk, StudioError> {
        text_chunk(
            field_id,
            self.text_source(self.texts.field(field_id)?)?,
            offset,
            max_bytes,
        )
    }
    fn text_source(&self, field: Text) -> Result<&str, StudioError> {
        Ok(match field {
            Text::Fingerprint => &self.data()?.config_fingerprint,
            Text::Account(index) => self.usage(index)?.account_id(),
            Text::Operation(index) => self.usage(index)?.last_operation_id(),
            Text::Message(index) => match self.usage(index)?.state() {
                AccountUsageState::MissingCredential(value) => value.message(),
                _ => return Err(wrong()),
            },
            Text::ErrorCode(index) | Text::ErrorMessage(index) => {
                let AccountUsageState::Failed(value) = self.usage(index)?.state() else {
                    return Err(wrong());
                };
                if matches!(field, Text::ErrorCode(_)) {
                    &value.error().code
                } else {
                    &value.error().message
                }
            }
            Text::Level(index) => self.quota(index)?.level.as_deref().ok_or_else(wrong)?,
            Text::Balance(account, index, part) => {
                let value = self
                    .balances_value(account)?
                    .balances
                    .get(index)
                    .ok_or_else(wrong)?;
                match part {
                    0 => &value.currency,
                    1 => &value.total_balance,
                    2 => &value.granted_balance,
                    3 => &value.topped_up_balance,
                    _ => return Err(wrong()),
                }
            }
            Text::Window(account, index) => match &self
                .quota(account)?
                .limits
                .get(index)
                .ok_or_else(wrong)?
                .window
            {
                ZhipuQuotaWindow::Other(value) => value,
                _ => return Err(wrong()),
            },
            Text::Detail(account, window, index) => {
                &self
                    .quota(account)?
                    .limits
                    .get(window)
                    .ok_or_else(wrong)?
                    .usage_details
                    .get(index)
                    .ok_or_else(wrong)?
                    .name
            }
            Text::SourceOperation => match &self.source.value.state {
                ObservedResource::Loading(value) => value.operation_id(),
                ObservedResource::Refreshing(value) => value.operation_id(),
                _ => return Err(wrong()),
            },
            Text::SourceCode | Text::SourceMessage => {
                let error = match &self.source.value.state {
                    ObservedResource::Degraded(value) => value.error(),
                    ObservedResource::Failed(value) => value.error(),
                    _ => return Err(wrong()),
                };
                if field == Text::SourceCode {
                    &error.code
                } else {
                    &error.message
                }
            }
        })
    }
}
fn wrong() -> StudioError {
    StudioError::invalid_argument("Unknown field, list or variant in this Usage scope")
}
