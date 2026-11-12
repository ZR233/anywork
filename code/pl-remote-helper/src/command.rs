use std::collections::BTreeMap;

use crate::{
    CaptureSpec, Child, ExecutionError, Executor, Output, ProcessExit, SpawnError, StartKnowledge,
};

#[derive(Debug, Clone, Copy, PartialEq, Eq, serde::Serialize, serde::Deserialize)]
pub enum Stdio {
    Null,
    Piped,
}

/// A structured program/argv invocation. Builder operations never perform I/O.
#[derive(Clone)]
pub struct Command {
    pub(crate) executor: Executor,
    pub(crate) program: String,
    pub(crate) arguments: Vec<String>,
    pub(crate) cwd: Option<String>,
    pub(crate) environment: BTreeMap<String, Option<String>>,
    pub(crate) clear_environment: bool,
    pub(crate) stdin: Option<Stdio>,
    pub(crate) stdout: Option<Stdio>,
    pub(crate) stderr: Option<Stdio>,
    pub(crate) capture: Option<CaptureSpec>,
}

impl std::fmt::Debug for Command {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Command")
            .field("executor", &self.executor.id())
            .finish_non_exhaustive()
    }
}

impl Command {
    pub(crate) fn new(executor: Executor, program: String) -> Self {
        Self {
            executor,
            program,
            arguments: Vec::new(),
            cwd: None,
            environment: BTreeMap::new(),
            clear_environment: false,
            stdin: None,
            stdout: None,
            stderr: None,
            capture: None,
        }
    }
    pub fn arg(&mut self, argument: impl Into<String>) -> &mut Self {
        self.arguments.push(argument.into());
        self
    }
    pub fn args(&mut self, arguments: impl IntoIterator<Item = impl Into<String>>) -> &mut Self {
        self.arguments.extend(arguments.into_iter().map(Into::into));
        self
    }
    pub fn current_dir(&mut self, directory: impl Into<String>) -> &mut Self {
        self.cwd = Some(directory.into());
        self
    }
    pub fn env(&mut self, key: impl Into<String>, value: impl Into<String>) -> &mut Self {
        self.environment.insert(key.into(), Some(value.into()));
        self
    }
    pub fn envs(
        &mut self,
        entries: impl IntoIterator<Item = (impl Into<String>, impl Into<String>)>,
    ) -> &mut Self {
        for (key, value) in entries {
            self.env(key, value);
        }
        self
    }
    pub fn env_remove(&mut self, key: impl Into<String>) -> &mut Self {
        self.environment.insert(key.into(), None);
        self
    }
    pub fn env_clear(&mut self) -> &mut Self {
        self.clear_environment = true;
        self.environment.clear();
        self
    }
    pub fn stdin(&mut self, stdio: Stdio) -> &mut Self {
        self.stdin = Some(stdio);
        self
    }
    pub fn stdout(&mut self, stdio: Stdio) -> &mut Self {
        self.stdout = Some(stdio);
        self
    }
    pub fn stderr(&mut self, stdio: Stdio) -> &mut Self {
        self.stderr = Some(stdio);
        self
    }
    pub fn capture(&mut self, capture: CaptureSpec) -> &mut Self {
        self.capture = Some(capture);
        self
    }

    pub async fn spawn(&mut self) -> Result<Child, SpawnError> {
        if self.executor.is_closed() {
            return Err(SpawnError {
                knowledge: StartKnowledge::NotStarted,
                cause: ExecutionError::Disconnected("executor is permanently closed".into()),
            });
        }
        self.validate().map_err(|cause| SpawnError {
            knowledge: StartKnowledge::NotStarted,
            cause,
        })?;
        match &self.executor.inner.backend {
            crate::executor::ExecutorBackend::Local => crate::native::spawn(self).await,
            crate::executor::ExecutorBackend::Remote(connection) => connection.spawn(self).await,
        }
    }
    pub async fn status(&mut self) -> Result<ProcessExit, ExecutionError> {
        if [self.stdin, self.stdout, self.stderr].contains(&Some(Stdio::Piped))
            || self.capture.is_some()
        {
            return Err(ExecutionError::InvalidInput(
                "status requires null stdio and no capture".into(),
            ));
        }
        self.spawn()
            .await
            .map_err(|error| error.cause)?
            .wait()
            .await
    }
    pub async fn output(&mut self) -> Result<Output, ExecutionError> {
        let mut command = self.clone();
        command.stdout.get_or_insert(Stdio::Piped);
        command.stderr.get_or_insert(Stdio::Piped);
        command
            .spawn()
            .await
            .map_err(|error| error.cause)?
            .wait_with_output()
            .await
    }
    fn validate(&self) -> Result<(), ExecutionError> {
        let invalid = |message: &str| ExecutionError::InvalidInput(message.into());
        if self.program.is_empty()
            || self.program.contains('\0')
            || self.arguments.iter().any(|arg| arg.contains('\0'))
            || self.cwd.as_ref().is_some_and(|cwd| cwd.contains('\0'))
        {
            return Err(invalid(
                "program, argv and cwd must be valid non-NUL strings",
            ));
        }
        for (key, value) in &self.environment {
            if key.is_empty()
                || key.contains(['=', '\0'])
                || value.as_ref().is_some_and(|value| value.contains('\0'))
            {
                return Err(invalid("invalid environment key or value"));
            }
        }
        if let Some(capture) = &self.capture
            && (self.stdout != Some(Stdio::Piped)
                || self.stderr != Some(Stdio::Piped)
                || capture.max_bytes == 0
                || capture.stdout_path == capture.stderr_path
                || capture.stdout_path.contains('\0')
                || capture.stderr_path.contains('\0'))
        {
            return Err(invalid(
                "capture needs distinct paths, a positive limit and two piped outputs",
            ));
        }
        Ok(())
    }
}
