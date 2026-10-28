//! A recorded first step fixes the lineage. All ordering and completion remain SeaORM-owned.

use super::steps::{Adopt, Audience9, File8, Publication10};
use super::{LedgerSchema, MigrationTrait};
use sea_orm::ConnectionTrait;
use sea_orm_migration::{MigrationStatus, MigratorTrait, MigratorTraitSelf};

pub(super) const LEDGER: &str = "m20261026_000001_bot_ledger_schema";
pub(super) const FILE8: &str = "m20261026_000002_bot_file8";
pub(super) const AUDIENCE9: &str = "m20261026_000003_bot_audience9";
pub(super) const PUBLICATION10: &str = "m20261026_000004_bot_publication10";

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Format {
    PreSix(i64),
    MainCard6,
    File6,
    File7,
    File8,
    Audience9,
    Publication10,
}

impl Format {
    pub(super) fn version(self) -> i64 {
        match self {
            Self::PreSix(version) => version,
            Self::MainCard6 | Self::File6 => 6,
            Self::File7 => 7,
            Self::File8 => 8,
            Self::Audience9 => 9,
            Self::Publication10 => 10,
        }
    }

    pub(super) fn adoption_name(self) -> &'static str {
        match self {
            Self::File6 => "m20261026_000001_adopt_bot_file6",
            Self::File7 => "m20261026_000001_adopt_bot_file7",
            Self::File8 => "m20261026_000001_adopt_bot_file8",
            Self::Audience9 => "m20261026_000001_adopt_bot_audience9",
            Self::Publication10 => "m20261026_000001_adopt_bot_publication10",
            Self::PreSix(_) | Self::MainCard6 => LEDGER,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub(super) enum Migrator {
    Main,
    Adopt(Format),
}

impl MigratorTraitSelf for Migrator {
    fn migrations(&self) -> Vec<Box<dyn MigrationTrait>> {
        match self {
            Self::Main => vec![
                Box::new(LedgerSchema),
                Box::new(File8),
                Box::new(Audience9),
                Box::new(Publication10),
            ],
            Self::Adopt(source) => {
                let mut steps: Vec<Box<dyn MigrationTrait>> = vec![Box::new(Adopt(*source))];
                if source.version() <= 8 {
                    steps.push(Box::new(Audience9));
                }
                if source.version() <= 9 {
                    steps.push(Box::new(Publication10));
                }
                steps
            }
        }
    }
}

// The catalog is only a read-only vocabulary for the official records API. It is never run.
struct Catalog;
impl MigratorTrait for Catalog {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        let mut steps = Migrator::Main.migrations();
        for format in ADOPTIONS {
            steps.push(Box::new(Adopt(format)));
        }
        steps
    }
}

const ADOPTIONS: [Format; 5] = [
    Format::File6,
    Format::File7,
    Format::File8,
    Format::Audience9,
    Format::Publication10,
];

impl Migrator {
    pub(super) fn for_source(source: Format) -> Self {
        match source {
            Format::PreSix(_) | Format::MainCard6 => Self::Main,
            source => Self::Adopt(source),
        }
    }

    pub(super) async fn recorded<C: ConnectionTrait>(db: &C) -> anyhow::Result<Option<Self>> {
        let applied = <Catalog as MigratorTrait>::get_applied_migrations_read_only(db).await?;
        if applied.is_empty() {
            return Ok(None);
        }
        let main = applied.iter().any(|step| step.name() == LEDGER);
        let adoptions: Vec<_> = ADOPTIONS
            .into_iter()
            .filter(|format| {
                applied
                    .iter()
                    .any(|step| step.name() == format.adoption_name())
            })
            .collect();
        anyhow::ensure!(
            usize::from(main) + adoptions.len() == 1,
            "unknown or mixed bot migration lineage; existing data preserved"
        );
        let migrator = if main {
            Self::Main
        } else {
            Self::Adopt(adoptions[0])
        };
        // SeaORM rejects records belonging to a different sequence. Additionally require a prefix:
        // the official API alone treats a later applied step with an earlier hole as valid.
        let statuses = migrator.get_migration_with_status_read_only(db).await?;
        let mut pending_seen = false;
        for step in statuses {
            match step.status() {
                MigrationStatus::Pending => pending_seen = true,
                MigrationStatus::Applied => anyhow::ensure!(
                    !pending_seen,
                    "bot migration completion records are not an ordered prefix"
                ),
            }
        }
        Ok(Some(migrator))
    }

    pub(super) async fn verify_format<C: ConnectionTrait>(
        self,
        db: &C,
        format: Format,
    ) -> anyhow::Result<()> {
        let applied = self.get_applied_migrations_read_only(db).await?;
        let last = applied
            .last()
            .ok_or_else(|| anyhow::anyhow!("missing bot lineage entry"))?;
        let expected = match last.name() {
            LEDGER => Format::MainCard6,
            FILE8 => Format::File8,
            AUDIENCE9 => Format::Audience9,
            PUBLICATION10 => Format::Publication10,
            name => match self {
                Self::Adopt(source) if name == source.adoption_name() => {
                    if source.version() < 8 {
                        Format::File8
                    } else {
                        source
                    }
                }
                _ => anyhow::bail!("bot lineage entry has no known output format"),
            },
        };
        anyhow::ensure!(
            expected == format,
            "bot format conflicts with completed migrations; existing data preserved"
        );
        Ok(())
    }
}
