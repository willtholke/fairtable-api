-- 002_seed_data.sql
-- Generates realistic seed data across all Fairtable bases/projects

TRUNCATE reviews, submissions, tasks;

-- ============================================================
-- Helper function for procedural seed generation
-- ============================================================
CREATE OR REPLACE FUNCTION _seed_project(
    p_base_id TEXT,
    p_task_names TEXT[],
    p_task_types TEXT[],
    p_tasker_ids INT[],
    p_reviewer_names TEXT[],
    p_start_date DATE,
    p_num_tasks INT,
    p_removed_ids INT[] DEFAULT ARRAY[]::INT[],
    p_removed_dates DATE[] DEFAULT ARRAY[]::DATE[]
) RETURNS void AS $$
DECLARE
    i INT;
    j INT;
    k INT;
    rec TEXT;
    sub_rec TEXT;
    rev_rec TEXT;
    t_created TIMESTAMP;
    t_due DATE;
    t_name TEXT;
    t_type TEXT;
    t_assigned INT;
    t_status TEXT;
    s_submitted TIMESTAMP;
    s_hours REAL;
    s_status TEXT;
    num_subs INT;
    r_reviewed TIMESTAMP;
    r_score REAL;
    r_status TEXT;
    r_reviewer TEXT;
    r_comments TEXT;
    available_taskers INT[];
    pass_comments TEXT[] := ARRAY[
        'Strong evaluation. Meets quality standards.',
        'Excellent work, thorough and well-reasoned.',
        'Accurate response with clear methodology.',
        'Meets all criteria. Solid output.',
        'High quality, no significant issues found.',
        'Well-structured analysis with good depth.',
        'Comprehensive evaluation, exceeds expectations.'
    ];
    cond_comments TEXT[] := ARRAY[
        'Acceptable with minor revisions needed.',
        'Mostly accurate but some gaps in reasoning.',
        'Good attempt, needs clarification on key points.',
        'Close to passing threshold, fix noted issues.',
        'Minor errors identified, revise and resubmit.',
        'Adequate but could be more thorough.',
        'Partial credit — see inline feedback.'
    ];
    fail_comments TEXT[] := ARRAY[
        'Does not meet minimum quality threshold.',
        'Significant errors in core evaluation.',
        'Incomplete analysis, missing key criteria.',
        'Needs substantial rework before approval.',
        'Below acceptable quality standard.',
        'Multiple factual errors, requires redo.',
        'Methodology flawed, see detailed notes.'
    ];
BEGIN
    FOR i IN 1..p_num_tasks LOOP
        -- Unique record ID
        rec := 'rec_' || substr(md5(random()::text || p_base_id || i::text || clock_timestamp()::text), 1, 12);

        -- Random created_at between start_date and now
        t_created := p_start_date::timestamp + (random() * (NOW() - p_start_date::timestamp));
        -- Due date: 3–17 days after creation, ~15% NULL
        IF random() < 0.15 THEN
            t_due := NULL;
        ELSE
            t_due := (t_created + (interval '3 days' + random() * interval '14 days'))::DATE;
        END IF;

        -- Cycle through task names and types
        t_name := p_task_names[1 + (i - 1) % array_length(p_task_names, 1)];
        t_type := p_task_types[1 + (i - 1) % array_length(p_task_types, 1)];

        -- Pick tasker, respecting removal dates
        available_taskers := p_tasker_ids;
        IF array_length(p_removed_ids, 1) IS NOT NULL THEN
            FOR k IN 1..array_length(p_removed_ids, 1) LOOP
                IF t_created::date >= p_removed_dates[k] THEN
                    available_taskers := array_remove(available_taskers, p_removed_ids[k]);
                END IF;
            END LOOP;
        END IF;

        IF array_length(available_taskers, 1) IS NULL THEN
            CONTINUE;
        END IF;

        t_assigned := available_taskers[1 + (i - 1) % array_length(available_taskers, 1)];

        -- Status distribution: ~10% todo, ~15% in_progress, ~40% done, ~35% reviewed
        IF random() < 0.10 THEN t_status := 'todo';
        ELSIF random() < 0.27 THEN t_status := 'in_progress';
        ELSIF random() < 0.65 THEN t_status := 'done';
        ELSE t_status := 'reviewed';
        END IF;

        -- Older tasks more likely done/reviewed
        IF t_created < NOW() - interval '60 days' AND t_status IN ('todo', 'in_progress') THEN
            IF random() < 0.80 THEN t_status := 'done'; END IF;
        END IF;

        INSERT INTO tasks (record_id, base_id, task_name, task_type, assigned_to, status, created_at, due_date)
        VALUES (rec, p_base_id, t_name, t_type, t_assigned, t_status, t_created, t_due);

        -- No submissions for todo tasks
        IF t_status = 'todo' THEN
            CONTINUE;
        END IF;

        -- 1–2 submissions per task
        num_subs := CASE WHEN random() < 0.70 THEN 1 ELSE 2 END;

        FOR j IN 1..num_subs LOOP
            sub_rec := 'rec_' || substr(md5(random()::text || 'sub' || i::text || j::text || clock_timestamp()::text), 1, 12);
            s_submitted := t_created + (interval '1 hour' + random() * interval '5 days');
            s_hours := round((0.25 + random() * 5.75)::numeric, 2);

            -- Submission status depends on task status
            IF t_status = 'in_progress' THEN
                s_status := 'pending';
            ELSIF t_status = 'reviewed' THEN
                s_status := CASE WHEN random() < 0.85 THEN 'approved' ELSE 'rejected' END;
            ELSE -- done
                IF random() < 0.65 THEN s_status := 'approved';
                ELSIF random() < 0.80 THEN s_status := 'pending';
                ELSE s_status := 'rejected';
                END IF;
            END IF;

            INSERT INTO submissions (record_id, base_id, task_record_id, submitted_by, submitted_at, hours_logged, status)
            VALUES (sub_rec, p_base_id, rec, t_assigned, s_submitted, s_hours, s_status);

            -- Review for ~65% of non-pending submissions
            IF s_status != 'pending' AND random() < 0.65 THEN
                rev_rec := 'rec_' || substr(md5(random()::text || 'rev' || i::text || j::text || clock_timestamp()::text), 1, 12);
                r_reviewed := s_submitted + (interval '30 minutes' + random() * interval '3 days');
                r_reviewer := p_reviewer_names[1 + (i + j) % array_length(p_reviewer_names, 1)];

                -- Score distribution: 80% in 65–90, 10% in 90–100, 10% in 30–65
                IF random() < 0.80 THEN
                    r_score := round((65 + random() * 25)::numeric, 1);
                ELSIF random() < 0.50 THEN
                    r_score := round((90 + random() * 10)::numeric, 1);
                ELSE
                    r_score := round((30 + random() * 35)::numeric, 1);
                END IF;

                -- Status based on score
                IF r_score >= 75 THEN r_status := 'pass';
                ELSIF r_score >= 55 THEN r_status := 'conditional_pass';
                ELSE r_status := 'fail';
                END IF;

                -- Comments based on status
                IF r_status = 'pass' THEN
                    r_comments := pass_comments[1 + floor(random() * array_length(pass_comments, 1))::int];
                ELSIF r_status = 'conditional_pass' THEN
                    r_comments := cond_comments[1 + floor(random() * array_length(cond_comments, 1))::int];
                ELSE
                    r_comments := fail_comments[1 + floor(random() * array_length(fail_comments, 1))::int];
                END IF;

                -- ~15% of reviews have NULL comments
                IF random() < 0.15 THEN r_comments := NULL; END IF;

                INSERT INTO reviews (record_id, base_id, submission_record_id, reviewed_by, score, status, comments, reviewed_at)
                VALUES (rev_rec, p_base_id, sub_rec, r_reviewer, r_score, r_status, r_comments, r_reviewed);
            END IF;
        END LOOP;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- Google Project 5: Medical Domain Evaluation
-- Taskers: Emily Chen (6), David Okonkwo (7), Sophie Dubois (8)
-- Reviewer role: Emily Chen
-- ~70 tasks, Oct 2024 – present
-- ============================================================
SELECT _seed_project(
    'base_google',
    ARRAY[
        'Evaluate cardiac diagnosis accuracy',
        'Review neurological symptom assessment',
        'Assess oncology treatment recommendation',
        'Evaluate radiology report interpretation',
        'Review pediatric symptom triage',
        'Assess pharmacological interaction analysis',
        'Evaluate surgical procedure explanation',
        'Review mental health assessment accuracy',
        'Assess emergency medicine triage response',
        'Evaluate dermatology condition diagnosis',
        'Review endocrinology lab interpretation',
        'Assess pulmonology case analysis',
        'Evaluate orthopedic injury assessment',
        'Review gastroenterology symptom evaluation',
        'Assess hematology blood panel analysis'
    ],
    ARRAY['medical_evaluation', 'domain_qa'],
    ARRAY[6, 7, 8],
    ARRAY['Emily Chen', 'David Okonkwo'],
    '2024-10-01',
    70
);


-- ============================================================
-- Google Project 6: Legal Domain Evaluation
-- Taskers: Jonathan Blake (9), Yuki Tanaka (10), Carlos Rodriguez (11), Eleanor Wright (18)
-- Reviewer role: Jonathan Blake
-- ~70 tasks, Oct 2024 – present
-- ============================================================
SELECT _seed_project(
    'base_google',
    ARRAY[
        'Evaluate contract clause analysis',
        'Review intellectual property assessment',
        'Assess criminal law case reasoning',
        'Evaluate regulatory compliance response',
        'Review employment law dispute analysis',
        'Assess tort liability evaluation',
        'Evaluate constitutional law interpretation',
        'Review international trade law analysis',
        'Assess corporate governance evaluation',
        'Evaluate family law case assessment',
        'Review bankruptcy proceeding analysis',
        'Assess environmental law compliance',
        'Evaluate real estate law interpretation',
        'Review immigration law case analysis',
        'Assess antitrust regulation evaluation'
    ],
    ARRAY['legal_evaluation', 'domain_qa'],
    ARRAY[9, 10, 11, 18],
    ARRAY['Jonathan Blake', 'Carlos Rodriguez'],
    '2024-10-01',
    70
);


-- ============================================================
-- xAI Project 7: Software Engineering Training Data
-- Active: Alex Thompson (1), Rajesh Sharma (3), Tomasz Kowalski (5)
-- Removed: Wei Zhang (2) on 2024-12-01, Maria Garcia (4) on 2024-11-15
-- ~50 tasks, Sep 2024 – present (older project)
-- ============================================================
SELECT _seed_project(
    'base_xai',
    ARRAY[
        'Generate Python sorting algorithm',
        'Review TypeScript API implementation',
        'Generate React component with state management',
        'Review database query optimization',
        'Generate REST API endpoint handler',
        'Review authentication middleware code',
        'Generate unit test suite for service layer',
        'Review CI/CD pipeline configuration',
        'Generate microservice architecture design',
        'Review code refactoring proposal',
        'Generate GraphQL schema and resolvers',
        'Review Docker containerization setup',
        'Generate async data processing pipeline',
        'Review security vulnerability patches',
        'Generate CLI tool implementation'
    ],
    ARRAY['code_generation', 'code_review'],
    ARRAY[1, 2, 3, 4, 5],
    ARRAY['Alex Thompson', 'Rajesh Sharma'],
    '2024-09-01',
    50,
    ARRAY[2, 4],
    ARRAY['2024-12-01'::DATE, '2024-11-15'::DATE]
);


-- ============================================================
-- xAI Project 8: Adversarial Prompt Testing (Red Team)
-- Taskers: Tomasz Kowalski (5), Yuki Tanaka (10), Alex Thompson (1)
-- ~50 tasks, Nov 2024 – present
-- ============================================================
SELECT _seed_project(
    'base_xai',
    ARRAY[
        'Test prompt injection resistance',
        'Evaluate harmful content filter bypass',
        'Test bias elicitation techniques',
        'Evaluate jailbreak attempt resilience',
        'Test data extraction vulnerability',
        'Evaluate social engineering prompt resistance',
        'Test role-playing boundary enforcement',
        'Evaluate encoded instruction handling',
        'Test multi-turn manipulation resistance',
        'Evaluate system prompt extraction defense',
        'Test unsafe code generation safeguards',
        'Evaluate misinformation generation controls',
        'Test personal information extraction defense',
        'Evaluate instruction hierarchy enforcement',
        'Test content policy circumvention resistance'
    ],
    ARRAY['red_team', 'adversarial_prompt'],
    ARRAY[5, 10, 1],
    ARRAY['Tomasz Kowalski', 'Yuki Tanaka'],
    '2024-11-01',
    50
);


-- ============================================================
-- Anthropic Project 9: Science Domain Expert Evaluation
-- Active: Fatima Al-Rashid (14), Henrik Lindqvist (15), Priya Nair (16),
--         Lucas Ferreira (17), David Okonkwo (7)
-- Removed: Emily Chen (6) on 2025-02-10 (workload conflict)
-- Reviewer role: Henrik Lindqvist
-- ~60 tasks, Nov 2024 – present
-- ============================================================
SELECT _seed_project(
    'base_anthropic',
    ARRAY[
        'Evaluate molecular biology explanation',
        'Review physics problem-solving accuracy',
        'Assess chemistry reaction analysis',
        'Evaluate neuroscience concept explanation',
        'Review genetics research interpretation',
        'Assess quantum mechanics problem solving',
        'Evaluate biochemistry pathway analysis',
        'Review ecology systems explanation',
        'Assess astrophysics concept accuracy',
        'Evaluate cell biology mechanism description',
        'Review organic chemistry synthesis analysis',
        'Assess thermodynamics problem solving',
        'Evaluate evolutionary biology reasoning',
        'Review materials science explanation',
        'Assess statistical mechanics analysis'
    ],
    ARRAY['science_evaluation', 'domain_qa'],
    ARRAY[6, 7, 14, 15, 16, 17],
    ARRAY['Henrik Lindqvist', 'Fatima Al-Rashid'],
    '2024-11-01',
    60,
    ARRAY[6],
    ARRAY['2025-02-10'::DATE]
);


-- ============================================================
-- Anthropic Project 10: Humanities & Social Science Evaluation
-- Taskers: Eleanor Wright (18), Soo-Jin Park (19), James Wilson (13)
-- Reviewer role: Eleanor Wright (team_lead)
-- ~60 tasks, Nov 2024 – present
-- ============================================================
SELECT _seed_project(
    'base_anthropic',
    ARRAY[
        'Evaluate historical event analysis',
        'Review philosophical argument assessment',
        'Assess psychological theory explanation',
        'Evaluate sociological research interpretation',
        'Review literary criticism accuracy',
        'Assess political theory analysis',
        'Evaluate anthropological perspective',
        'Review linguistic analysis accuracy',
        'Assess economic theory explanation',
        'Evaluate art history interpretation',
        'Review religious studies analysis',
        'Assess cultural studies perspective',
        'Evaluate ethics case analysis',
        'Review comparative literature assessment',
        'Assess media studies analysis'
    ],
    ARRAY['humanities_evaluation', 'domain_qa'],
    ARRAY[13, 18, 19],
    ARRAY['Eleanor Wright', 'Soo-Jin Park'],
    '2024-11-01',
    60
);


-- Cleanup helper function
DROP FUNCTION _seed_project;
