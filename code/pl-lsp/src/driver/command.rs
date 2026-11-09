//! Generic data-backed initialize/configuration adapter. No installation or version probe.
use super::LspServerDriver;
use serde_json::Value;

pub(crate) struct CommandDriver {
    initialization_options: Value,
    settings: Value,
}
impl CommandDriver {
    pub(crate) fn new(initialization_options: Value, settings: Value) -> Self {
        Self {
            initialization_options,
            settings,
        }
    }
}
impl LspServerDriver for CommandDriver {
    fn initialization_options(&self) -> Value {
        self.initialization_options.clone()
    }
    fn configuration_response(&self, section: Option<&str>) -> Value {
        let Some(section) = section.filter(|section| !section.is_empty()) else {
            return self.settings.clone();
        };
        section
            .split('.')
            .try_fold(&self.settings, |value, key| value.get(key))
            .cloned()
            .unwrap_or(Value::Null)
    }
}
