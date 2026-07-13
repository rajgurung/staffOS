# Feature: Workstream-based Run Passports

## Goal

Align the implementation with SPEC.md §14: one living Run Passport per Workstream
(branch), versioned by session completion — instead of one passport per session.
The passport certifies "is this branch sound?", so a branch with five sessions gets
one cumulative assessment with five version snapshots, not five disconnected
assessments where only the last one is visible. Sessions become pure evidence
containers ("just a time container, not in the hierarchy").

## Honest claim (blind spots)

StaffOS only observes what flows through Claude Code hooks. Commits made outside
sessions, manual edits, rebases, and pre-`staffos init` work are invisible. The
passport therefore certifies **the observed AI-assisted work on this branch**, not
the branch's full git state — copy in the UI should say so ("based on N captured
sessions"). Closing the gap is a follow-up, not part of this refactor: the CLI's
Stop hook can send `git diff --numstat` vs the merge-base (paths + counts only,
per the privacy model) so the passport can report observed coverage and raise an
"unobserved changes on branch" missing-check.

## Scope

### In Scope
- `RunPassport` belongs to `Workstream` (required, unique — DB-enforced), not to a session.
- `PassportVersion` gains `agent_session_id` (nullable) recording which session triggered it.
- `PassportGenerator` takes a workstream and does a **full rebuild** from all the
  workstream's events on every session stop, then snapshots a version
  (`trigger: session_completed`). Council/manual reassessment keeps updating the
  same living passport.
- **Rolling window for eternal branches:** for `main`/`master` workstreams, the
  generator only assesses events from the last 7 days. Feature branches assess
  everything (their lifecycle ends at merge). Event history is never trimmed —
  the window only bounds what the assessment reads.
- Sessions with no workstream (`branch_name: unknown`) get no passport (already true; keep it).
- View/controller sweep: session pages show their event timeline plus a link to the
  branch passport they contributed to; passport pages anchor on the workstream.
- Data migration: per workstream keep the newest passport as the living one, fold older
  passports into its version history (ordered by `created_at`), re-link their
  documents/decision_logs/council_reviews to the survivor, then enforce the unique index.
- Update seeds and tests to the new shape.

### Out of Scope
- Trimming or archiving old events.
- Auto-detecting branch merges (workstream status stays manually driven).
- Changing risk rules, LLM modes, or the council flow itself.
- Multi-workstream sessions UI (a session that switches branches already routes events
  per-branch; each affected workstream just regenerates on stop).

## Technical Approach

Rails 8 monolith, existing stack. Key moves:

1. **Migration:** `run_passports` — make `workstream_id` NOT NULL, add unique index,
   drop `agent_session_id`. `passport_versions` — add `agent_session_id` (nullable FK).
   Data migration folds existing per-session passports as described above
   (prod currently has exactly one passport, so this is near-trivial live).
2. **Models:** `RunPassport belongs_to :workstream` (required) + `has_one :project,
   through: :workstream`; `Workstream has_one :run_passport`; drop `current_passport`
   (and its preload dance from PR #27); `AgentSession` loses `run_passport`.
   `duration_minutes` moves to `PassportVersion` (its triggering session's duration).
3. **Generator:** `PassportGenerator.new(workstream, window: …)` reads
   `workstream.run_events` (windowed for main/master), upserts the living passport,
   returns it. Intent = earliest `prompt_submitted` in the assessed window;
   smart-summary/council enrichment unchanged, operating on the living passport.
4. **Hooks stop action:** `PassportGenerator.new(ws).generate!` then
   `passport.create_version!(trigger: "session_completed", agent_session: session)`.
   Same for the legacy `api/v1/sessions_controller` path.
5. **Views/controllers:** grep-driven sweep of the ~15 views referencing
   `session.run_passport` / `current_passport`; `run_passports_controller#reassess`
   goes through the workstream.

## Key Flows

1. **Multi-session branch:** session 1 stops → passport v1 (readiness 42%, High).
   Session 2 adds tests, stops → full rebuild sees all events → passport now 68%,
   Medium; v2 records "readiness 42% → 68%, risk High → Medium" and which session
   drove it. The workstream page tells the maturity story; `changes_from_previous`
   already computes it.
2. **Direct-to-main work:** sessions on `main` roll into a 7-day-window passport —
   recent unreviewed main work stays visible without months of blended history.
3. **Council review:** runs against the branch passport; completion creates a
   version (`trigger: council_completed`) with no triggering session.

## Success Criteria
- [x] DB enforces one passport per workstream; sessions have no passport FK.
- [x] A two-session workstream test proves cumulative assessment (files/tests from
      both sessions) and per-session version deltas.
- [x] Rolling-window test: events older than 7 days on `main` don't affect the
      assessment; the same events on a feature branch do.
- [x] A `branch_name: unknown` session produces events but no passport.
- [ ] Existing prod passport and its document/decision/council links survive migration.
- [x] Full suite green; smoke tests cover the reworked session/workstream/passport pages.

## Risks and Unknowns
- **View fallout** (~15 views read passports): mitigated by the existing
  `pages_smoke_test` plus the sweep being mechanical (readers like `risk_level`,
  `files_touched` are unchanged on the passport itself).
- **Full rebuild cost:** fine at current volumes; if a workstream grows huge the
  windowing mechanism built for main is the escape hatch.
- **Reassess/council flows** touch the passport in place — living passport is updated,
  never recreated, so council reviews and document links can't orphan. The generator
  must upsert, not delete-and-recreate.
- **Seeds** build per-session passports today and will fail loudly until updated.

## Open Questions
- None blocking. (Deferred separately: transcript-noise session filtering,
  `capture` honoring the privacy config, and branch-coverage git metadata from the
  CLI Stop hook — tracked as follow-ups, not part of this work.)
