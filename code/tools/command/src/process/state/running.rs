use serde::{Deserialize, Serialize};

use super::CommandProcessHealth;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub struct RunningCommandProcess {
    health: CommandProcessHealth,
}

impl RunningCommandProcess {
    pub fn healthy() -> Self {
        Self {
            health: CommandProcessHealth::Healthy,
        }
    }

    pub fn health(&self) -> &CommandProcessHealth {
        &self.health
    }

    pub fn record_output_error(&mut self, message: String) {
        self.health = CommandProcessHealth::OutputFailed { message };
    }
}
