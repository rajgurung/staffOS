# Product Brief: StaffOS

## 1. Working title

StaffOS

## 2. One line positioning

StaffOS is the trust, review, and documentation layer for AI-assisted engineering work.

StaffOS turns every Claude Code, Cursor, Codex, or agent coding session into a verified engineering record: intent, context, files touched, tests run, risks found, decisions made, and human review required.

## 3. The problem

AI coding tools are becoming powerful, but their work is often messy, invisible, and hard to trust.

Developers now use tools like Claude Code, Cursor, GitHub Copilot agents, Codex, Devin, and other AI agents to write code, review code, refactor, investigate bugs, and generate docs.

But teams still struggle with:

1. What did the agent actually do?
2. Which files did it inspect or change?
3. Did it run tests?
4. Did it introduce risk?
5. Was the change aligned with previous architecture decisions?
6. Should this require human approval?
7. Was the AI-generated change documented?
8. Can we audit this later?
9. Did the session create reusable knowledge?
10. How much did the run cost?

## 4. The insight

The main opportunity is not "Help AI write code." That space is crowded.

The stronger opportunity is: "Help humans trust, review, govern, and remember AI-written or AI-assisted code."

AI coding agents are becoming the worker.

StaffOS becomes:

1. The control plane
2. The reviewer
3. The audit trail
4. The decision log
5. The documentation engine
6. The team memory
7. The quality gate

## 5. Target user

Primary user: Senior software engineers, tech leads, staff engineers, and engineering managers using AI coding tools.

Secondary users: Engineering teams adopting AI coding tools and needing visibility, review processes, and governance.

Early niche: Software teams working in high-trust environments (healthtech, fintech, infrastructure-heavy SaaS, enterprise platforms, regulated or semi-regulated domains, teams with strong PR review standards).

## 6. Core product concept

StaffOS connects to AI coding sessions and creates a structured record called a Run Passport.

A Run Passport answers:

1. What was the goal?
2. What context was used?
3. Which agent or model worked on it?
4. Which files were inspected?
5. Which files were changed?
6. Which commands were run?
7. Which tests passed or failed?
8. What risks were detected?
9. What decisions were made?
10. What documentation should be created?
11. Is this ready for PR?
12. Does this require human review?

## 7. Main product artifact: Run Passport

Example:

- Intent: Refactor AI inference callback retry handling.
- Agent: Claude Code
- Branch: rr-553-ai-hardening
- Files touched: app/services/inference_callback_handler.rb, spec/services/inference_callback_handler_spec.rb
- Validation: RSpec passed, Lint not run, Migration not applicable, Security-sensitive files no, Auth-sensitive files no, Infrastructure files no
- Risk level: Medium
- Why: The change touches retry behaviour. Duplicate callbacks and idempotency need careful review.
- Detected gaps: Missing idempotency test, Missing correlation ID in logs, Retry behaviour not captured in an ADR
- Decision extracted: Automatically retry failed inference callbacks when provider response is empty or malformed.
- Human review required: Yes
- Recommended before merge: Add idempotency spec, Add correlation ID to structured logs, Save retry behaviour as decision log, Add PR note explaining failure path

## 8. Why this is different from a normal dashboard

A normal dashboard says: "Claude Code ran."

StaffOS says: "Claude Code made this kind of change, with this risk level, these tests, these missing checks, and this documentation requirement."

StaffOS specialises in engineering work:

1. Code changes
2. Pull request readiness
3. Test evidence
4. Architecture decisions
5. Risk review
6. Human approval
7. Documentation capture

## 9. Product wedge

Turn Claude Code sessions into verified engineering Run Passports.

The first product promise: Connect Claude Code. Run your normal AI coding workflow. StaffOS captures the work, scores risk, checks evidence, and creates a review-ready Run Passport.

## 10. First use case: AI-assisted PR readiness

A developer uses Claude Code to refactor a service.

StaffOS captures: Initial prompt, Branch, Files read, Files changed, Commands run, Test results, Final Claude response, Git diff summary, Risk signals, Documentation suggestions

Then StaffOS generates: Run Passport, PR summary, Reviewer checklist, Risk notes, Suggested follow-up tasks, Optional ADR or decision log

## 11. User journey

Step 1: Create project (name, tech stack, team rules)
Step 2: Connect repo (staffos init creates .staffos.yml, Claude Code hook config, project token)
Step 3: Use Claude Code normally
Step 4: StaffOS captures the session via Claude Code hooks
Step 5: StaffOS generates Run Passport
Step 6: User reviews output (risk level, test evidence, missing checks, files touched, PR summary, documentation recommendations, human review requirement)
Step 7: Save documentation (decision log, ADR, PR summary, risk item, action item, project memory)

## 12. Core MVP features

Feature 1: StaffOS local connector (CLI: staffos login, init, status, disconnect, passport)
Feature 2: Claude Code hook integration (SessionStart, UserPromptSubmit, Tool use before/after, Stop, SessionEnd)
Feature 3: Run event store (session_started, prompt_submitted, file_read, file_edited, command_run, test_run, tool_failed, agent_response, session_completed, passport_generated)
Feature 4: Run Passport generator (Intent, Context, Files touched, Commands, Test evidence, Risk score, Missing checks, Human review requirement, Documentation suggestions)
Feature 5: Risk rule engine (deterministic rules: auth files = high, payment files = high, infra files = high, tests not run = warning, production config changed = high, etc.)
Feature 6: Documentation engine (PR summary, Decision log, ADR draft, Risk register item, Action items, Team update)
Feature 7: StaffOS dashboard (Active runs, Recent Run Passports, Risk distribution, Human review required, Documentation created, Project memory, AI usage and cost)

## 13. Technical architecture

Claude Code -> Claude Code hooks -> staffos local connector -> StaffOS ingestion API -> Run event store -> Risk engine -> Passport generator -> Documentation engine -> Web dashboard

Stack: Rails 8, Hotwire/Turbo/Stimulus, Tailwind CSS, PostgreSQL

## 14. Data model

### Workstream Architecture

A Workstream maps 1:1 to a Git branch. It is the primary organizing entity in StaffOS. Multiple sessions on the same branch share a Workstream. All artifacts (passports, documents, decisions, memory) belong to the Workstream until it merges, at which point they promote to the project level.

```
PROJECT
|
+-- WORKSTREAM (auto-created from git branch name)
|   |   name: "rr-553-ai-hardening"
|   |   title: "Harden retry logic" (human-editable)
|   |   status: active | in_review | merged | archived
|   |   project_id
|   |
|   +-- EVENTS (the raw atoms, routed here by branch)
|   |   |   event_type: file_read, file_edited, command_run, etc.
|   |   |   session_id (which session it came from)
|   |   |   workstream_id (which workstream it belongs to)
|   |   |   occurred_at
|   |   |   payload
|   |
|   +-- PASSPORT (one living passport per workstream)
|   |   |   intent, summary, risk_level, readiness_score
|   |   |   files_touched, test_summary
|   |   |   human_review_required
|   |   |   last_assessed_at
|   |   |
|   |   +-- COUNCIL REVIEWS (6 AI persona reviews)
|   |   +-- VERSIONS (immutable point-in-time snapshots)
|   |       "v1: Session 1 done - 42% ready, High risk"
|   |       "v2: Session 2 done - 68% ready, Medium risk"
|   |       "v3: Council completed - 85% ready, Low risk"
|   |
|   +-- DOCUMENTS (ADRs, PR summaries)
|   +-- DECISION LOGS
|   +-- MEMORY ITEMS
|
+-- WORKSTREAM (another branch)
|   ...
|
+-- PROJECT-LEVEL (promoted after merge)
    +-- DOCUMENTS
    +-- DECISION LOGS
    +-- MEMORY ITEMS


SESSION (just a time container, not in the hierarchy)
|   external_session_id
|   started_at, completed_at
|   provider, agent_name
|   References events it produced (but doesn't own them)
```

### Key design decisions

- Events belong to Workstreams, not Sessions. The session is the source tag.
- One Passport per Workstream. It mutates as new events come in.
- Passport Versions are immutable snapshots capturing point-in-time state.
- On merge, documents and decisions promote to project level but keep their workstream link as history.
- A single Claude Code session can touch multiple Workstreams if the user switches branches mid-session.

### Model definitions

- Project (name, repo_name, tech_stack, risk_rules, documentation_preferences)
- Workstream (project_id, branch_name, title, status, description, merged_at)
- AgentSession (project_id, workstream_id, external_session_id, provider, agent_name, branch_name, status, started_at, completed_at, metadata)
- RunEvent (agent_session_id, workstream_id, event_type, occurred_at, payload, source)
- RunPassport (agent_session_id, workstream_id, intent, summary, risk_level, readiness_score, human_review_required, test_summary, files_touched, missing_checks, recommended_actions, current_version, last_assessed_at, review_mode)
- PassportVersion (run_passport_id, version_number, readiness_score, risk_level, summary, files_touched, test_summary, missing_checks, risk_signals, trigger, changes_from_previous)
- CouncilReview (run_passport_id, workstream_id, persona, status, findings, recommendation, risk_assessment, score, completed_at)
- Document (project_id, workstream_id, run_passport_id, document_type, title, content_markdown, status)
- DecisionLog (project_id, workstream_id, run_passport_id, title, context, decision, rationale, consequences, status)
- MemoryItem (project_id, workstream_id, memory_type, content, confidence, expires_at)

## 15. Risk scoring model

Start deterministic.

Low risk: Documentation only, Test only, Small refactor with tests passing
Medium risk: Service logic changed, Retry logic changed, Background job changed, API contract changed, Test coverage partial
High risk: Auth or permission changed, Payment or billing changed, Infrastructure or CI changed, Database migration added, Production config changed, Security-sensitive dependency changed, No tests run on behavioural change

## 16. LLM usage strategy

Three modes:
- Passive mode: No extra LLM call. Record events and show timeline.
- Smart summary mode: Use a cheaper model to summarise session and extract risks.
- Full council mode: Use multiple reviewers (Staff Engineer, SRE, Security, Product, Documentation). Opt-in or triggered only for high-risk runs.

## 17. Privacy model

Default: Source code stays local unless user explicitly allows upload.

StaffOS stores: File paths, file categories, diff metadata, test command summaries, agent activity metadata, final approved summaries, decision logs, risk findings.

StaffOS avoids storing: Entire source files, secrets, environment variables, full terminal output, full diffs unless explicitly enabled.

## 18. MVP scope

Build: StaffOS Rails app, dashboard, user and project setup, CLI connector, Claude Code hook ingestion, run timeline, Run Passport generation, basic deterministic risk rules, PR summary generator, decision log generator, documentation library.

Do not build: Full multi-agent marketplace, no-code workflow builder, Slack/Jira/Linear integration, GitHub write access, enterprise SSO, autonomous code execution, multi-provider agent routing, complex eval framework, team analytics.

## 19. V1 roadmap

Phase 1 - Local POC: CLI, hooks, event ingestion, run timeline, basic summary
Phase 2 - Run Passport: Files touched, commands, tests, risk score, missing checks, PR summary
Phase 3 - Documentation brain: Decision logs, ADR drafts, risk items, action items, project memory
Phase 4 - Smart review: LLM-powered multi-persona review (opt-in)
Phase 5 - Team workflow: GitHub PR comment, Linear ticket link, shared dashboard, weekly report, team policy rules

## 20. Success metric

The MVP succeeds if a user can say: "After using Claude Code, I now have a clean record of what happened, what risk exists, what needs review, and what documentation should be saved."
