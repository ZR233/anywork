CREATE TABLE agent_evaluations (
            agent_id TEXT PRIMARY KEY NOT NULL,
            parent_agent_id TEXT NOT NULL,
            account_id TEXT NOT NULL,
            model_id TEXT NOT NULL,
            effort TEXT,
            profile_id TEXT NOT NULL,
            mode TEXT NOT NULL CHECK(mode IN ('profile','automatic')),
            preference TEXT NOT NULL CHECK(preference IN ('economy','balanced','fast')),
            turn_id TEXT NOT NULL,
            revision INTEGER NOT NULL CHECK(revision > 0),
            task_category TEXT NOT NULL,
            outcome TEXT NOT NULL CHECK(outcome IN ('passed','failed','notRated')),
            quality INTEGER,
            instruction_following INTEGER,
            comment TEXT NOT NULL CHECK(length(trim(comment)) > 0 AND length(comment) <= 300),
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL,
            CHECK ((outcome = 'notRated' AND quality IS NULL AND instruction_following IS NULL)
                OR (outcome IN ('passed','failed') AND quality IS NOT NULL AND instruction_following IS NOT NULL AND quality BETWEEN 1 AND 5
                    AND instruction_following BETWEEN 1 AND 5))
        );
CREATE INDEX idx_agent_evaluations_model_updated ON agent_evaluations
            (account_id, model_id, updated_at DESC, agent_id DESC);
