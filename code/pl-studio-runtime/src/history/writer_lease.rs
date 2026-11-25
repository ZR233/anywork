use std::{fs::File, io, path::Path};

use super::{HistoryError, Result};

/// The migration and the live writer share one physical, process-exclusive lease.
pub(super) struct WriterLease {
    file: Option<File>,
}

impl WriterLease {
    pub(super) fn acquire(history_path: &Path) -> Result<Self> {
        let mut lock_path = history_path.as_os_str().to_os_string();
        lock_path.push(".writer.lock");
        let lock_path = Path::new(&lock_path);
        if let Some(parent) = lock_path.parent()
            && !parent.as_os_str().is_empty()
        {
            std::fs::create_dir_all(parent)?;
        }
        let file = File::options()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .open(lock_path)?;
        file.try_lock()
            .map_err(|error| HistoryError::Conflict(format!("history writer lease: {error}")))?;
        Ok(Self { file: Some(file) })
    }

    pub(super) fn release(&mut self) -> io::Result<()> {
        if let Some(file) = &self.file {
            // Closing just this descriptor can leave flock held by a concurrently forked
            // child until exec/exit. Unlock the shared open-file description explicitly.
            file.unlock()?;
            self.file.take();
        }
        Ok(())
    }
}

impl Drop for WriterLease {
    fn drop(&mut self) {
        if let Err(error) = self.release() {
            tracing::error!(%error, "释放历史写入租约失败");
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn release_allows_the_next_writer_while_a_duplicate_handle_survives() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("history.sqlite");
        let mut lease = WriterLease::acquire(&path)?;
        let inherited = lease.file.as_ref().unwrap().try_clone()?;
        assert!(matches!(
            WriterLease::acquire(&path),
            Err(HistoryError::Conflict(_))
        ));
        lease.release()?;
        let next = WriterLease::acquire(&path)?;
        drop(lease);
        drop(inherited);
        assert!(matches!(
            WriterLease::acquire(&path),
            Err(HistoryError::Conflict(_))
        ));
        drop(next);
        WriterLease::acquire(&path)?;
        Ok(())
    }

    #[test]
    fn dropping_a_migration_lease_releases_even_with_a_duplicate_handle() -> Result<()> {
        let temp = tempfile::tempdir()?;
        let path = temp.path().join("history.sqlite");
        let lease = WriterLease::acquire(&path)?;
        let inherited = lease.file.as_ref().unwrap().try_clone()?;
        drop(lease);
        let next = WriterLease::acquire(&path)?;
        drop(inherited);
        assert!(matches!(
            WriterLease::acquire(&path),
            Err(HistoryError::Conflict(_))
        ));
        drop(next);
        Ok(())
    }
}
