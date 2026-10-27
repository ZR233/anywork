CREATE TABLE thread_tool_tasks (
        thread_id TEXT NOT NULL, task_id TEXT NOT NULL, call_id TEXT NOT NULL,
        task_envelope TEXT NOT NULL, task_hash TEXT NOT NULL,
        delivery_sequence INTEGER, delivery_position INTEGER,
        PRIMARY KEY(thread_id,task_id), UNIQUE(thread_id,call_id));
    CREATE TABLE thread_tool_task_resources (
        thread_id TEXT NOT NULL, call_id TEXT NOT NULL, reference_hash TEXT NOT NULL,
        reference_envelope TEXT NOT NULL,
        PRIMARY KEY(thread_id,call_id,reference_hash));
