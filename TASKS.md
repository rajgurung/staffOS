# Tasks

Generated from specs/workstream-passports.md on 2026-07-13.

## Sequential foundation (each depends on the previous)

- [x] **Task 1: Schema migration + data fold** — Make `run_passports.workstream_id`
  NOT NULL with a unique index and drop `run_passports.agent_session_id`; add nullable
  `passport_versions.agent_session_id` (FK). In the same migration, fold existing
  per-session passports: per workstream keep the newest passport as the living one,
  convert older siblings into `passport_versions` on the survivor (ordered by
  `created_at`, stamping their triggering session), re-link their
  documents/decision_logs/council_reviews to the survivor, and null out passports on
  workstream-less sessions before the NOT NULL lands. Up-only (raise on rollback).
  — Files: `db/migrate/*`, `db/schema.rb`
  — Verify: `bin/rails db:seed && bin/rails db:migrate` on a fresh dev DB; folded
  version counts match pre-migration passport counts.

- [x] **Task 2: Model layer** — `RunPassport belongs_to :workstream` (required),
  `has_one :project, through: :workstream`, drop the session association; move
  `duration_minutes` to `PassportVersion` (via its `agent_session`); `PassportVersion
  belongs_to :agent_session, optional: true`; `Workstream has_one :run_passport`
  (replacing `has_many` + `current_passport`), `risk_trend`/`readiness_trend` read
  passport versions, simplify `all_files_touched` (single passport); `AgentSession`
  loses `has_one :run_passport`. — Depends on: Task 1
  — Files: `app/models/run_passport.rb`, `app/models/workstream.rb`,
  `app/models/agent_session.rb`, `app/models/passport_version.rb`
  — Verify: `bin/rails test test/models`

- [x] **Task 3: PassportGenerator rework** — Constructor takes a workstream; full
  rebuild from `workstream.run_events` on every call, upserting the living passport
  (never delete/recreate — council reviews and document links must survive). 7-day
  rolling window when `branch_name` is `main`/`master`; intent = earliest
  `prompt_submitted` in the assessed window; `apply_smart_summary!` unchanged in
  behavior. `RiskScorer` input (a passport) is untouched. — Depends on: Task 2
  — Files: `app/services/passport_generator.rb`
  — Verify: `bin/rails test test/services`

- [x] **Task 4: Ingestion + controller call sites** — `Api::V1::HooksController#stop`
  and `Api::V1::SessionsController` generate via the session's workstream and create
  a version with `trigger: "session_completed"` + the triggering session (skip
  entirely when the session has no workstream); `RunPassportsController#reassess`
  (and any session-based passport lookups in controllers) go through the workstream.
  — Depends on: Task 3
  — Files: `app/controllers/api/v1/hooks_controller.rb`,
  `app/controllers/api/v1/sessions_controller.rb`,
  `app/controllers/run_passports_controller.rb`, other controllers per grep
  — Verify: `bin/rails test test/integration/api`

## Parallel Group (after Task 4 — disjoint view files)

- [ ] **Task 5: Session-side views** — `agent_sessions/index|show` become event
  timeline + "contributed to [branch passport]" link (passport panel moves out);
  `projects/_tree_session` and `projects/show` read readiness/risk from the
  workstream's passport. Passport copy says "based on N captured sessions" per the
  spec's honest-claim section. — Files: `app/views/agent_sessions/*`,
  `app/views/projects/*`, `app/controllers/agent_sessions_controller.rb`,
  `app/controllers/projects_controller.rb`
  — Verify: `bin/rails test test/integration/pages_smoke_test.rb`

- [ ] **Task 6: Workstream/passport-side views** — `workstreams/index|show` anchor on
  the single living passport (no more latest-of-many); `run_passports/index|show`,
  dashboard, risk_cockpit, search, settings views updated for workstream-anchored
  passports; version timeline shows which session drove each version.
  — Files: `app/views/workstreams/*`, `app/views/run_passports/*`,
  `app/views/dashboard/*`, `app/views/risk_cockpit/*`, `app/views/search/*`,
  `app/views/settings/*`, matching controllers
  — Verify: `bin/rails test test/integration/pages_smoke_test.rb`

## Parallel Group (after Task 4 — data + tests)

- [ ] **Task 7: Seeds** — `db/seeds.rb` builds one passport per workstream with
  per-session versions (helper at line ~30 currently creates per-session passports).
  — Files: `db/seeds.rb`
  — Verify: `bin/rails db:reset` succeeds on a dev database.

- [ ] **Task 8: Test suite alignment + new behavior tests** — Update
  `test_helper.rb#make_passport` (build via workstream), fix existing tests; add:
  two-session workstream proves cumulative files/tests and version deltas
  ("readiness X → Y"); rolling-window test (old events on `main` excluded, same
  events on a feature branch included); `branch_name: unknown` session produces
  events but no passport; unique-passport-per-workstream DB constraint test.
  — Files: `test/test_helper.rb`, `test/models/*`, `test/services/*`,
  `test/integration/*`
  — Verify: the new tests fail before Tasks 1–4 and pass after.

## Final

- [ ] **Task 9: Integration pass** — Full suite green (`bin/rails test`), click-through
  of project → workstream → passport → session pages via the dev server, spec's
  success-criteria checklist ticked off in `specs/workstream-passports.md`; confirm
  the deploy path (Railway `preDeployCommand` runs the data-fold migration against
  prod's single existing passport). — Depends on: all
  — Verify: all success criteria in specs/workstream-passports.md checked.
