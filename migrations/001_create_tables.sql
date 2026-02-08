-- 001_create_tables.sql
-- Creates tasks, submissions, and reviews tables for Fairtable API

DROP TABLE IF EXISTS reviews CASCADE;
DROP TABLE IF EXISTS submissions CASCADE;
DROP TABLE IF EXISTS tasks CASCADE;

CREATE TABLE tasks (
    record_id   VARCHAR PRIMARY KEY,
    base_id     VARCHAR NOT NULL,
    task_name   VARCHAR NOT NULL,
    task_type   VARCHAR NOT NULL,
    assigned_to INTEGER NOT NULL,
    status      VARCHAR NOT NULL CHECK (status IN ('todo', 'in_progress', 'done', 'reviewed')),
    created_at  TIMESTAMP NOT NULL DEFAULT NOW(),
    due_date    DATE
);

CREATE TABLE submissions (
    record_id       VARCHAR PRIMARY KEY,
    base_id         VARCHAR NOT NULL,
    task_record_id  VARCHAR NOT NULL REFERENCES tasks(record_id),
    submitted_by    INTEGER NOT NULL,
    submitted_at    TIMESTAMP NOT NULL DEFAULT NOW(),
    hours_logged    REAL NOT NULL,
    status          VARCHAR NOT NULL CHECK (status IN ('pending', 'approved', 'rejected'))
);

CREATE TABLE reviews (
    record_id             VARCHAR PRIMARY KEY,
    base_id               VARCHAR NOT NULL,
    submission_record_id  VARCHAR NOT NULL REFERENCES submissions(record_id),
    reviewed_by           VARCHAR NOT NULL,
    score                 REAL NOT NULL CHECK (score >= 0 AND score <= 100),
    status                VARCHAR NOT NULL CHECK (status IN ('pass', 'fail', 'conditional_pass')),
    comments              TEXT,
    reviewed_at           TIMESTAMP NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_tasks_base_id ON tasks(base_id);
CREATE INDEX idx_tasks_status ON tasks(status);
CREATE INDEX idx_tasks_assigned_to ON tasks(assigned_to);
CREATE INDEX idx_submissions_base_id ON submissions(base_id);
CREATE INDEX idx_submissions_task_record_id ON submissions(task_record_id);
CREATE INDEX idx_reviews_base_id ON reviews(base_id);
CREATE INDEX idx_reviews_submission_record_id ON reviews(submission_record_id);
