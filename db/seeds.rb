# This seed file is DEMO DATA for local development only — it creates users with
# well-known passwords and fake projects. It must never run against production.
# Skip gracefully (not abort) so `db:prepare` on a fresh prod DB still succeeds.
unless Rails.env.development?
  puts "Skipping db/seeds.rb: development-only demo data (current env: #{Rails.env})."
  return
end

# Default users. All demo data is owned by SEED_OWNER_EMAIL when set (created
# with password "password123" if missing), else by the raj@staffos.dev demo user.
owner_email = ENV["SEED_OWNER_EMAIL"].presence || "raj@staffos.dev"
owner = User.find_or_create_by!(email: owner_email) { |u| u.name = "Raj Gurung"; u.password = "password123"; u.password_confirmation = "password123" }
User.find_or_create_by!(email: "raj@local.dev") { |u| u.name = "Raj"; u.password = "staffos123"; u.password_confirmation = "staffos123" }

# Projects (owned by the demo user)
project = Project.find_or_create_by!(name: "AI Peer Review Pipeline") do |p|
  p.user = owner
  p.repo_name = "staffos/ai-peer-review"
  p.tech_stack = "Ruby on Rails, PostgreSQL, Sidekiq, RSpec"
  p.risk_rules = { "auth_files" => "high", "payment_files" => "high", "infra_files" => "high", "no_tests" => "warning", "retry_logic" => "medium" }
end

Project.find_or_create_by!(name: "StaffOS Platform") do |p|
  p.user = owner
  p.repo_name = "rajgurung/staffOS"
  p.tech_stack = "Ruby on Rails, PostgreSQL, Tailwind CSS, Hotwire"
  p.risk_rules = { "auth_files" => "high", "migration" => "high", "config" => "medium" }
end

# Re-running with a different SEED_OWNER_EMAIL adopts the existing demo projects.
Project.where(name: ["AI Peer Review Pipeline", "StaffOS Platform"]).where.not(user: owner).update_all(user_id: owner.id)

ApiToken.find_or_create_by!(name: "CLI Token") { |t| t.project = project }

# Helper to seed an agent session and its run events. Events default to the
# session's workstream but can override it per-event (ed[:workstream]) to model
# branch-hopping sessions. status: "active" leaves the session in flight.
def seed_session(project:, ws:, branch_name:, session_id:, started_ago:, duration_minutes:, model:, tokens:, events_data:, status: "completed")
  session = AgentSession.find_or_create_by!(external_session_id: session_id) do |s|
    s.project = project
    s.workstream = ws
    s.provider = "claude_code"
    s.agent_name = "Claude Code"
    s.branch_name = branch_name
    s.status = status
    s.started_at = started_ago
    s.completed_at = status == "completed" ? started_ago + duration_minutes.minutes : nil
    s.metadata = { model: model, tokens_used: tokens }
  end

  base = session.started_at
  events_data.each do |ed|
    RunEvent.find_or_create_by!(agent_session: session, event_type: ed[:event_type], occurred_at: base + ed[:offset].seconds) do |e|
      e.payload = ed[:payload]
      e.source = "claude_code"
      e.workstream = ed[:workstream] || ws
    end
  end

  session
end

# Helper to seed a workstream with sessions, events, passport, and versions.
# Pass prior_session (session fields plus summary/risk_level/readiness/missing_checks)
# to seed an earlier session and a v1 passport version showing progression.
def seed_workstream(project:, branch_name:, title:, description:, status:, merged_at: nil,
                    session_id:, started_ago:, duration_minutes:, model: "claude-sonnet-4-20250514", tokens:,
                    intent:, summary:, risk_level:, readiness:, review_required:, review_mode: "passive",
                    test_summary:, files_touched:, missing_checks:, recommended_actions:, events_data:,
                    prior_session: nil, run_council: false)
  ws = Workstream.find_or_create_for_branch(project: project, branch_name: branch_name)
  ws.update!(title: title, description: description, status: status, merged_at: merged_at)

  session = seed_session(project: project, ws: ws, branch_name: branch_name, session_id: session_id,
                         started_ago: started_ago, duration_minutes: duration_minutes, model: model,
                         tokens: tokens, events_data: events_data)

  passport = RunPassport.find_or_create_by!(workstream: ws) do |p|
    p.intent = intent
    p.summary = summary
    p.risk_level = risk_level
    p.readiness_score = readiness
    p.human_review_required = review_required
    p.review_mode = review_mode
    p.test_summary = test_summary
    p.files_touched = files_touched
    p.missing_checks = missing_checks
    p.recommended_actions = recommended_actions
  end

  if passport.passport_versions.empty?
    if prior_session
      early = seed_session(project: project, ws: ws, branch_name: branch_name, model: model,
                           session_id: prior_session[:session_id], started_ago: prior_session[:started_ago],
                           duration_minutes: prior_session[:duration_minutes], tokens: prior_session[:tokens],
                           events_data: prior_session[:events_data])
      # Snapshot v1 with the earlier session's assessment, then restore the current values for v2.
      passport.update!(summary: prior_session[:summary], risk_level: prior_session[:risk_level],
                       readiness_score: prior_session[:readiness], missing_checks: prior_session[:missing_checks])
      passport.create_version!(trigger: "session_completed", agent_session: early)
      passport.update!(summary: summary, risk_level: risk_level, readiness_score: readiness, missing_checks: missing_checks)
    end
    passport.create_version!(trigger: "session_completed", agent_session: session)
  end

  if run_council && passport.passport_versions.where(trigger: "council_completed").none?
    CouncilRunner.new(passport).run!
    passport.create_version!(trigger: "council_completed")
  end

  # Without an API key the council/summary run on heuristics (cost 0). For a
  # representative demo, stamp realistic LLM usage on the AI-backed passports so
  # the dashboard's "AI usage and cost" panel reflects real spend.
  seed_cost = ->(model, input, output) do
    rates = LlmClient::PRICING[model]
    (((input / 1_000_000.0 * rates[:input]) + (output / 1_000_000.0 * rates[:output])) * 100).round
  end

  if review_mode == "full_council"
    model = LlmClient::COUNCIL_MODEL
    passport.council_reviews.completed.find_each do |r|
      input, output = rand(2400..3600), rand(300..700)
      r.update!(source: "llm", model: model, input_tokens: input,
                output_tokens: output, cost_cents: seed_cost.call(model, input, output))
    end
    totals = passport.council_reviews.completed
    passport.update!(input_tokens: totals.sum(:input_tokens), output_tokens: totals.sum(:output_tokens),
                     cost_cents: totals.sum(:cost_cents))
  elsif review_mode == "smart_summary"
    model = LlmClient::SUMMARY_MODEL
    input, output = rand(1200..2000), rand(200..400)
    passport.update!(summary_source: "llm", input_tokens: input, output_tokens: output,
                     cost_cents: seed_cost.call(model, input, output))
  end

  { workstream: ws, session: session, passport: passport }
end

# ── Workstream 1: Retry hardening ──
ws1 = seed_workstream(
  project: project, branch_name: "rr-553-ai-hardening",
  title: "Harden retry logic", description: "Refactor inference callback handler with exponential backoff retry logic and idempotency.",
  status: "active", session_id: "demo-session-001", started_ago: 2.hours.ago, duration_minutes: 10, tokens: 48200,
  intent: "Review and harden the inference callback retry path. Check tests and observability.",
  summary: "Refactored inference callback handler with exponential backoff retry logic, added idempotency key validation to prevent duplicate processing, and improved structured logging with correlation IDs across the callback pipeline. All existing tests pass, 12 new test cases added.",
  risk_level: "Medium", readiness: 72, review_required: true,
  test_summary: { "status" => "passed", "total" => 142, "passed" => 142, "failed" => 0, "new_tests" => 12, "coverage" => 87.3 },
  files_touched: [
    { "path" => "app/services/inference_callback_handler.rb", "category" => "service", "additions" => 42, "deletions" => 11 },
    { "path" => "spec/services/inference_callback_handler_spec.rb", "category" => "test", "additions" => 45, "deletions" => 3 },
    { "path" => "app/services/ai_provider_client.rb", "category" => "service", "additions" => 0, "deletions" => 0 },
    { "path" => "config/initializers/retry_config.rb", "category" => "config", "additions" => 8, "deletions" => 0 },
    { "path" => "app/controllers/api/v1/callbacks_controller.rb", "category" => "controller", "additions" => 0, "deletions" => 0 },
    { "path" => "app/services/callback_logger.rb", "category" => "service", "additions" => 18, "deletions" => 5 },
    { "path" => "app/services/inference_callback_handler.rb", "category" => "service", "additions" => 6, "deletions" => 1 }
  ],
  missing_checks: [
    { "check" => "Idempotency edge case test for concurrent callbacks", "severity" => "high" },
    { "check" => "Correlation ID propagation to downstream services", "severity" => "medium" },
    { "check" => "Retry behaviour not captured in an ADR", "severity" => "medium" },
    { "check" => "Lint check not run", "severity" => "low" }
  ],
  recommended_actions: [
    { "action" => "Add idempotency spec for concurrent callback scenario", "priority" => "high" },
    { "action" => "Add correlation ID to structured logs", "priority" => "high" },
    { "action" => "Save retry behaviour as ADR", "priority" => "medium" },
    { "action" => "Add PR note explaining failure path", "priority" => "medium" },
    { "action" => "Run linter before merge", "priority" => "low" }
  ],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "rr-553-ai-hardening", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 30, payload: { prompt: "Review and harden the inference callback retry path. Check tests and observability." } },
    { event_type: "file_read", offset: 60, payload: { file: "app/services/inference_callback_handler.rb", lines: 142 } },
    { event_type: "file_read", offset: 75, payload: { file: "spec/services/inference_callback_handler_spec.rb", lines: 89 } },
    { event_type: "file_read", offset: 90, payload: { file: "app/services/ai_provider_client.rb", lines: 203 } },
    { event_type: "file_edited", offset: 180, payload: { file: "app/services/inference_callback_handler.rb", additions: 24, deletions: 8 } },
    { event_type: "file_edited", offset: 240, payload: { file: "spec/services/inference_callback_handler_spec.rb", additions: 45, deletions: 3 } },
    { event_type: "command_run", offset: 300, payload: { command: "bundle exec rspec spec/services/inference_callback_handler_spec.rb", exit_code: 0 } },
    { event_type: "file_edited", offset: 360, payload: { file: "app/services/inference_callback_handler.rb", additions: 12, deletions: 2 } },
    { event_type: "file_edited", offset: 400, payload: { file: "config/initializers/retry_config.rb", additions: 8, deletions: 0 } },
    { event_type: "command_run", offset: 420, payload: { command: "bundle exec rspec", exit_code: 0, examples: 142, failures: 0 } },
    { event_type: "file_read", offset: 450, payload: { file: "app/controllers/api/v1/callbacks_controller.rb", lines: 67 } },
    { event_type: "file_edited", offset: 500, payload: { file: "app/services/callback_logger.rb", additions: 18, deletions: 5 } },
    { event_type: "file_edited", offset: 540, payload: { file: "app/services/inference_callback_handler.rb", additions: 6, deletions: 1 } },
    { event_type: "agent_response", offset: 600, payload: { summary: "Hardened retry logic with exponential backoff, added idempotency key check, improved structured logging with correlation IDs." } },
    { event_type: "session_completed", offset: 620, payload: { duration_seconds: 620, files_changed: 7 } }
  ],
  # Earlier session on the same branch: first pass had no tests and no idempotency,
  # so v1 of the passport reads 45/High before the follow-up session brings it to 72/Medium.
  prior_session: {
    session_id: "demo-session-000", started_ago: 1.day.ago, duration_minutes: 6, tokens: 21400,
    summary: "First pass at the retry path: replaced the fixed retry count with exponential backoff in the callback handler. No new tests yet, idempotency handling still missing.",
    risk_level: "High", readiness: 45,
    missing_checks: [
      { "check" => "No tests for new retry behaviour", "severity" => "high" },
      { "check" => "Duplicate callback processing not prevented", "severity" => "high" },
      { "check" => "Idempotency edge case test for concurrent callbacks", "severity" => "high" },
      { "check" => "Correlation ID propagation to downstream services", "severity" => "medium" },
      { "check" => "Retry behaviour not captured in an ADR", "severity" => "medium" },
      { "check" => "Lint check not run", "severity" => "low" }
    ],
    events_data: [
      { event_type: "session_started", offset: 0, payload: { branch: "rr-553-ai-hardening", model: "claude-sonnet-4-20250514" } },
      { event_type: "prompt_submitted", offset: 20, payload: { prompt: "Replace the fixed retry count in the inference callback handler with exponential backoff." } },
      { event_type: "file_read", offset: 50, payload: { file: "app/services/inference_callback_handler.rb", lines: 130 } },
      { event_type: "file_edited", offset: 140, payload: { file: "app/services/inference_callback_handler.rb", additions: 19, deletions: 6 } },
      { event_type: "command_run", offset: 220, payload: { command: "bundle exec rspec spec/services/inference_callback_handler_spec.rb", exit_code: 1, examples: 9, failures: 2 } },
      { event_type: "file_edited", offset: 300, payload: { file: "app/services/inference_callback_handler.rb", additions: 4, deletions: 2 } },
      { event_type: "command_run", offset: 330, payload: { command: "bundle exec rspec spec/services/inference_callback_handler_spec.rb", exit_code: 0, examples: 9, failures: 0 } },
      { event_type: "agent_response", offset: 350, payload: { summary: "Replaced fixed retry with exponential backoff. Idempotency and new tests still outstanding." } },
      { event_type: "session_completed", offset: 360, payload: { duration_seconds: 360, files_changed: 1 } }
    ]
  },
  run_council: true
)

# ── Workstream 2: OAuth token refresh ──
ws2 = seed_workstream(
  project: project, branch_name: "fix/oauth-token-refresh",
  title: "Fix OAuth token refresh race condition", description: "Concurrent token refresh requests causing 401 cascades in the inference pipeline.",
  status: "active", session_id: "demo-session-002", started_ago: 5.hours.ago, duration_minutes: 8, tokens: 32100,
  intent: "Fix OAuth token refresh race condition causing 401 cascades",
  summary: "Added mutex lock around token refresh, implemented token cache with TTL, and added retry-after-refresh logic for downstream API calls.",
  risk_level: "High", readiness: 54, review_required: true,
  test_summary: { "status" => "passed", "total" => 89, "passed" => 89, "failed" => 0, "new_tests" => 6 },
  files_touched: [
    { "path" => "app/services/oauth_token_manager.rb", "category" => "service", "additions" => 38, "deletions" => 12 },
    { "path" => "app/services/api_client.rb", "category" => "service", "additions" => 15, "deletions" => 3 },
    { "path" => "spec/services/oauth_token_manager_spec.rb", "category" => "test", "additions" => 42, "deletions" => 0 },
    { "path" => "config/initializers/oauth.rb", "category" => "config", "additions" => 5, "deletions" => 1 }
  ],
  missing_checks: [
    { "check" => "Auth-sensitive files modified (oauth_token_manager)", "severity" => "high" },
    { "check" => "Mutex lock could cause deadlock under heavy load", "severity" => "high" },
    { "check" => "No load test evidence", "severity" => "medium" }
  ],
  recommended_actions: [
    { "action" => "Run load test to verify no deadlocks under concurrency", "priority" => "high" },
    { "action" => "Security review of token storage changes", "priority" => "high" },
    { "action" => "Add metrics for token refresh rate", "priority" => "medium" },
    { "action" => "Document token refresh flow in ADR", "priority" => "low" }
  ],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "fix/oauth-token-refresh", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 20, payload: { prompt: "Fix the OAuth token refresh race condition causing 401 cascades in the inference pipeline." } },
    { event_type: "file_read", offset: 45, payload: { file: "app/services/oauth_token_manager.rb", lines: 87 } },
    { event_type: "file_read", offset: 60, payload: { file: "app/services/api_client.rb", lines: 124 } },
    { event_type: "file_read", offset: 80, payload: { file: "config/initializers/oauth.rb", lines: 18 } },
    { event_type: "file_edited", offset: 150, payload: { file: "app/services/oauth_token_manager.rb", additions: 38, deletions: 12 } },
    { event_type: "file_edited", offset: 220, payload: { file: "app/services/api_client.rb", additions: 15, deletions: 3 } },
    { event_type: "file_edited", offset: 260, payload: { file: "config/initializers/oauth.rb", additions: 5, deletions: 1 } },
    { event_type: "file_edited", offset: 310, payload: { file: "spec/services/oauth_token_manager_spec.rb", additions: 42, deletions: 0 } },
    { event_type: "command_run", offset: 350, payload: { command: "bundle exec rspec spec/services/oauth_token_manager_spec.rb", exit_code: 0, examples: 12, failures: 0 } },
    { event_type: "command_run", offset: 400, payload: { command: "bundle exec rspec", exit_code: 0, examples: 89, failures: 0 } },
    { event_type: "agent_response", offset: 430, payload: { summary: "Added mutex lock around token refresh, implemented token cache with TTL, and added retry-after-refresh logic." } },
    { event_type: "session_completed", offset: 450, payload: { duration_seconds: 450, files_changed: 4 } }
  ]
)

# ── Workstream 3: Stripe webhook idempotency ──
seed_workstream(
  project: project, branch_name: "feature/stripe-webhook-idempotency",
  title: "Add Stripe webhook idempotency", description: "Ensure duplicate Stripe webhook events do not create duplicate charges or subscriptions.",
  status: "in_review", session_id: "demo-session-003", started_ago: 1.day.ago, duration_minutes: 9, tokens: 55800,
  intent: "Add idempotency to Stripe webhook handler to prevent duplicate charges",
  summary: "Implemented idempotency key tracking via Redis, added deduplication check before processing charge.succeeded and invoice.paid events, and comprehensive test coverage for all webhook event types.",
  risk_level: "High", readiness: 78, review_required: true, review_mode: "full_council",
  test_summary: { "status" => "passed", "total" => 156, "passed" => 156, "failed" => 0, "new_tests" => 24 },
  files_touched: [
    { "path" => "app/controllers/webhooks/stripe_controller.rb", "category" => "controller", "additions" => 28, "deletions" => 8 },
    { "path" => "app/services/stripe_webhook_processor.rb", "category" => "service", "additions" => 65, "deletions" => 0 },
    { "path" => "app/services/idempotency_store.rb", "category" => "service", "additions" => 32, "deletions" => 0 },
    { "path" => "spec/services/stripe_webhook_processor_spec.rb", "category" => "test", "additions" => 89, "deletions" => 0 },
    { "path" => "spec/services/idempotency_store_spec.rb", "category" => "test", "additions" => 45, "deletions" => 0 },
    { "path" => "config/initializers/redis.rb", "category" => "config", "additions" => 3, "deletions" => 0 }
  ],
  missing_checks: [
    { "check" => "Payment-related files modified", "severity" => "high" },
    { "check" => "Redis dependency added without failover config", "severity" => "medium" }
  ],
  recommended_actions: [
    { "action" => "PCI compliance review for payment flow changes", "priority" => "high" },
    { "action" => "Add Redis failover configuration", "priority" => "medium" },
    { "action" => "Add Stripe webhook signature verification test", "priority" => "medium" },
    { "action" => "Document idempotency strategy in ADR", "priority" => "low" }
  ],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "feature/stripe-webhook-idempotency", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 15, payload: { prompt: "Add idempotency to our Stripe webhook handler. We are getting duplicate charges from webhook retries." } },
    { event_type: "file_read", offset: 40, payload: { file: "app/controllers/webhooks/stripe_controller.rb", lines: 56 } },
    { event_type: "file_read", offset: 55, payload: { file: "app/services/billing_service.rb", lines: 203 } },
    { event_type: "file_read", offset: 70, payload: { file: "config/initializers/redis.rb", lines: 12 } },
    { event_type: "file_edited", offset: 120, payload: { file: "app/services/idempotency_store.rb", additions: 32, deletions: 0 } },
    { event_type: "file_edited", offset: 200, payload: { file: "app/services/stripe_webhook_processor.rb", additions: 65, deletions: 0 } },
    { event_type: "file_edited", offset: 280, payload: { file: "app/controllers/webhooks/stripe_controller.rb", additions: 28, deletions: 8 } },
    { event_type: "file_edited", offset: 320, payload: { file: "config/initializers/redis.rb", additions: 3, deletions: 0 } },
    { event_type: "command_run", offset: 360, payload: { command: "bundle exec rspec spec/services/stripe_webhook_processor_spec.rb", exit_code: 0, examples: 18, failures: 0 } },
    { event_type: "file_edited", offset: 400, payload: { file: "spec/services/stripe_webhook_processor_spec.rb", additions: 89, deletions: 0 } },
    { event_type: "file_edited", offset: 440, payload: { file: "spec/services/idempotency_store_spec.rb", additions: 45, deletions: 0 } },
    { event_type: "command_run", offset: 480, payload: { command: "bundle exec rspec", exit_code: 0, examples: 156, failures: 0 } },
    { event_type: "agent_response", offset: 510, payload: { summary: "Implemented idempotency key tracking via Redis with deduplication for charge.succeeded and invoice.paid events." } },
    { event_type: "session_completed", offset: 530, payload: { duration_seconds: 530, files_changed: 6 } }
  ],
  run_council: true
)

# ── Workstream 4: Structured logging (merged) ──
ws4 = seed_workstream(
  project: project, branch_name: "feature/structured-logging",
  title: "Add structured logging with correlation IDs", description: "Replace unstructured log lines with JSON structured logs and propagate correlation IDs across service boundaries.",
  status: "merged", merged_at: 3.days.ago,
  session_id: "demo-session-004", started_ago: 4.days.ago, duration_minutes: 5, tokens: 18400,
  intent: "Replace unstructured logging with JSON structured logs and correlation IDs",
  summary: "Introduced LogFormatter with JSON output, added CorrelationId middleware, and updated all service classes to use structured logging.",
  risk_level: "Low", readiness: 92, review_required: false, review_mode: "smart_summary",
  test_summary: { "status" => "passed", "total" => 134, "passed" => 134, "failed" => 0, "new_tests" => 8 },
  files_touched: [
    { "path" => "app/middleware/correlation_id.rb", "category" => "service", "additions" => 22, "deletions" => 0 },
    { "path" => "lib/log_formatter.rb", "category" => "other", "additions" => 35, "deletions" => 0 },
    { "path" => "config/initializers/logging.rb", "category" => "config", "additions" => 8, "deletions" => 3 },
    { "path" => "spec/middleware/correlation_id_spec.rb", "category" => "test", "additions" => 28, "deletions" => 0 }
  ],
  missing_checks: [],
  recommended_actions: [
    { "action" => "Verify log output in staging before production deploy", "priority" => "low" }
  ],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "feature/structured-logging", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 10, payload: { prompt: "Replace unstructured logging with JSON structured logs and add correlation IDs across services." } },
    { event_type: "file_read", offset: 30, payload: { file: "config/initializers/logging.rb", lines: 8 } },
    { event_type: "file_read", offset: 45, payload: { file: "app/services/inference_callback_handler.rb", lines: 142 } },
    { event_type: "file_edited", offset: 100, payload: { file: "lib/log_formatter.rb", additions: 35, deletions: 0 } },
    { event_type: "file_edited", offset: 150, payload: { file: "app/middleware/correlation_id.rb", additions: 22, deletions: 0 } },
    { event_type: "file_edited", offset: 180, payload: { file: "config/initializers/logging.rb", additions: 8, deletions: 3 } },
    { event_type: "file_edited", offset: 210, payload: { file: "spec/middleware/correlation_id_spec.rb", additions: 28, deletions: 0 } },
    { event_type: "command_run", offset: 240, payload: { command: "bundle exec rspec", exit_code: 0, examples: 134, failures: 0 } },
    { event_type: "agent_response", offset: 260, payload: { summary: "Introduced LogFormatter with JSON output, added CorrelationId middleware, updated all services." } },
    { event_type: "session_completed", offset: 270, payload: { duration_seconds: 270, files_changed: 4 } }
  ]
)

# Documents and decisions for workstream 1
passport = ws1[:passport]
ws = ws1[:workstream]

Document.find_or_create_by!(title: "ADR: Exponential Backoff Retry Strategy") do |d|
  d.project = project; d.workstream = ws; d.run_passport = passport; d.document_type = "adr"; d.status = "published"
  d.content_markdown = "# ADR: Exponential Backoff Retry Strategy\n\n## Status\nAccepted\n\n## Context\nThe inference callback handler was using a fixed retry count of 3 with no backoff. Under load, this caused thundering herd problems.\n\n## Decision\nImplement exponential backoff with jitter. Maximum 5 attempts, base delay 1s, max delay 30s.\n\n## Consequences\n- Reduced load on AI providers during transient failures\n- Slightly increased latency for retried requests\n- Need to monitor retry metrics in New Relic"
end

Document.find_or_create_by!(title: "PR Summary: Harden inference callback retry path") do |d|
  d.project = project; d.workstream = ws; d.run_passport = passport; d.document_type = "pr_summary"; d.status = "published"
  d.content_markdown = "## Summary\n- Replace fixed retry with exponential backoff (max 5 attempts)\n- Add idempotency key check to prevent duplicate callback processing\n- Add correlation ID to structured logs across callback pipeline\n- 12 new test cases covering retry edge cases\n\n## Test Plan\n- [x] Existing RSpec suite passes (142 examples, 0 failures)\n- [x] New idempotency tests cover concurrent callback scenarios\n- [ ] Manual verification of retry behaviour under load"
end

DecisionLog.find_or_create_by!(title: "Retry failed inference callbacks on empty/malformed responses") do |d|
  d.project = project; d.workstream = ws; d.run_passport = passport; d.status = "active"
  d.context = "AI inference providers occasionally return empty or malformed responses during high load."
  d.decision = "Automatically retry failed inference callbacks when provider response is empty or malformed, using exponential backoff with a maximum of 5 attempts."
  d.rationale = "Transient failures from AI providers are common and recoverable."
  d.consequences = "Increased resilience to transient failures. Slightly higher latency for retried requests."
end

DecisionLog.find_or_create_by!(title: "Require idempotency keys for all callback endpoints") do |d|
  d.project = project; d.workstream = ws; d.run_passport = passport; d.status = "active"
  d.context = "Duplicate callbacks were observed in production when AI providers retry delivery after network timeouts."
  d.decision = "Require idempotency keys on all callback endpoints. Process each key exactly once using a Redis-backed deduplication check."
  d.rationale = "Without idempotency, duplicate callbacks caused duplicate work items and incorrect billing calculations."
  d.consequences = "All callback producers must include an idempotency key. Redis dependency added. Keys expire after 24 hours."
end

MemoryItem.find_or_create_by!(content: "Inference callbacks now require idempotency keys for all providers.") { |m| m.project = project; m.workstream = ws; m.memory_type = "decision"; m.confidence = 0.95 }
MemoryItem.find_or_create_by!(content: "Service orchestration is preferred over model callbacks for AI workflow coordination.") { |m| m.project = project; m.memory_type = "convention"; m.confidence = 0.9 }
MemoryItem.find_or_create_by!(content: "All external callbacks need idempotency protection. Retry behaviour must have tests.") { |m| m.project = project; m.memory_type = "constraint"; m.confidence = 1.0 }
MemoryItem.find_or_create_by!(content: "AI workflow logs need correlation ID for tracing across service boundaries.") { |m| m.project = project; m.memory_type = "pattern"; m.confidence = 0.85 }

# ── Branch coverage: ws1 has unobserved changes (warning line + honest gap),
# ws4 is fully observed (green line) ──
ws1[:passport].update!(branch_coverage: {
  "observed" => 5, "branch_files" => 7,
  "unobserved_paths" => ["app/models/callback_receipt.rb", "db/migrate/20260712_add_callback_receipts.rb"]
})
ws4[:passport].update!(branch_coverage: { "observed" => 4, "branch_files" => 4, "unobserved_paths" => [] })

# ── Multi-branch session: started on rr-553 but hopped to the oauth branch
# mid-flight (fixing an api_client conflict), so it fed BOTH passports.
# Exercises the session page's per-branch passport grid + hop chips. ──
multi = seed_session(
  project: project, ws: ws1[:workstream], branch_name: "rr-553-ai-hardening",
  session_id: "demo-session-005", started_ago: 35.minutes.ago, duration_minutes: 12,
  model: "claude-sonnet-4-20250514", tokens: 39600,
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "rr-553-ai-hardening", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 25, payload: { prompt: "Wire the retry handler's correlation IDs through api_client. If the oauth branch conflicts, fix it there directly." } },
    { event_type: "file_read", offset: 60, payload: { file: "app/services/inference_callback_handler.rb", lines: 158 } },
    { event_type: "file_edited", offset: 150, payload: { file: "app/services/inference_callback_handler.rb", additions: 9, deletions: 2 } },
    { event_type: "command_run", offset: 210, payload: { command: "git switch fix/oauth-token-refresh", exit_code: 0 } },
    { event_type: "file_edited", offset: 280, payload: { file: "app/services/api_client.rb", additions: 11, deletions: 4 }, workstream: ws2[:workstream] },
    { event_type: "command_run", offset: 340, payload: { command: "bundle exec rspec spec/services/api_client_spec.rb", exit_code: 0, examples: 14, failures: 0 }, workstream: ws2[:workstream] },
    { event_type: "command_run", offset: 380, payload: { command: "git switch rr-553-ai-hardening", exit_code: 0 } },
    { event_type: "file_edited", offset: 450, payload: { file: "spec/services/inference_callback_handler_spec.rb", additions: 12, deletions: 0 } },
    { event_type: "command_run", offset: 520, payload: { command: "bundle exec rspec", exit_code: 0, examples: 168, failures: 0 } },
    { event_type: "agent_response", offset: 660, payload: { summary: "Correlation IDs wired through api_client; conflicting oauth-branch change fixed in place. Both branches green." } },
    { event_type: "session_completed", offset: 700, payload: { duration_seconds: 700, files_changed: 3 } }
  ]
)
[ws1, ws2].each do |h|
  h[:passport].create_version!(trigger: "session_completed", agent_session: multi) unless h[:passport].passport_versions.exists?(agent_session: multi)
end

# ── Workstream 5: brand-new branch, session still in flight, NO passport yet.
# Exercises the dashboard Active Runs panel and the workstream page without a
# passport strip. ──
ws5 = Workstream.find_or_create_for_branch(project: project, branch_name: "feature/model-fallback-chain")
ws5.update!(title: "Model fallback chain", description: "Fall back to a secondary model provider when the primary times out twice in a row.", status: "active")
seed_session(
  project: project, ws: ws5, branch_name: "feature/model-fallback-chain",
  session_id: "demo-session-006", started_ago: 7.minutes.ago, duration_minutes: 0, status: "active",
  model: "claude-sonnet-4-20250514", tokens: 8400,
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "feature/model-fallback-chain", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 20, payload: { prompt: "Add a fallback chain: if the primary model times out twice, route to the secondary provider." } },
    { event_type: "file_read", offset: 55, payload: { file: "app/services/ai_provider_client.rb", lines: 203 } },
    { event_type: "file_read", offset: 90, payload: { file: "config/initializers/providers.rb", lines: 31 } },
    { event_type: "file_edited", offset: 240, payload: { file: "app/services/ai_provider_client.rb", additions: 17, deletions: 3 } },
    { event_type: "file_edited", offset: 350, payload: { file: "app/services/provider_fallback.rb", additions: 29, deletions: 0 } }
  ]
)

# ── Workstream 6: archived housekeeping branch — exercises the Archived filter
# and a quiet low-risk passport with no council. ──
seed_workstream(
  project: project, branch_name: "chore/dependency-bumps",
  title: "Quarterly dependency bumps", description: "Routine gem updates: rails patch, rubocop, faraday.",
  status: "archived", session_id: "demo-session-007", started_ago: 12.days.ago, duration_minutes: 4, tokens: 9200,
  intent: "Bump outdated gems and fix any deprecation warnings",
  summary: "Updated 9 gems (all patch/minor). Fixed two deprecation warnings in the Faraday middleware setup. Full suite green.",
  risk_level: "Low", readiness: 88, review_required: false,
  test_summary: { "status" => "passed", "total" => 134, "passed" => 134, "failed" => 0, "new_tests" => 0 },
  files_touched: [
    { "path" => "Gemfile", "category" => "config", "additions" => 9, "deletions" => 9 },
    { "path" => "Gemfile.lock", "category" => "config", "additions" => 61, "deletions" => 58 },
    { "path" => "config/initializers/faraday.rb", "category" => "config", "additions" => 4, "deletions" => 6 }
  ],
  missing_checks: [{ "check" => "Dependency files changed — run bundler-audit", "severity" => "medium" }],
  recommended_actions: [{ "action" => "Run bundler-audit before merge", "priority" => "medium" }],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "chore/dependency-bumps", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 15, payload: { prompt: "Bump outdated gems and fix any deprecation warnings." } },
    { event_type: "command_run", offset: 40, payload: { command: "bundle outdated", exit_code: 0 } },
    { event_type: "file_edited", offset: 90, payload: { file: "Gemfile", additions: 9, deletions: 9 } },
    { event_type: "command_run", offset: 130, payload: { command: "bundle update --conservative", exit_code: 0 } },
    { event_type: "file_edited", offset: 180, payload: { file: "config/initializers/faraday.rb", additions: 4, deletions: 6 } },
    { event_type: "command_run", offset: 220, payload: { command: "bundle exec rspec", exit_code: 0, examples: 134, failures: 0 } },
    { event_type: "session_completed", offset: 240, payload: { duration_seconds: 240, files_changed: 3 } }
  ]
)

# ── Workstream 7: red path — failing tests, blocked merge. Exercises the
# danger states: Failed tests card, red event dots, low readiness. ──
seed_workstream(
  project: project, branch_name: "fix/flaky-payment-spec",
  title: "Fix flaky payment capture spec", description: "payment_capture_spec fails intermittently under parallel test runs; suspect shared Redis state.",
  status: "active", session_id: "demo-session-008", started_ago: 45.minutes.ago, duration_minutes: 11, tokens: 27300,
  intent: "Make payment_capture_spec deterministic under parallel runs",
  summary: "Isolated the shared Redis fixture per test process and froze time around capture-window assertions. Two failures remain in the concurrent refund path — the underlying race in RefundProcessor is still unresolved.",
  risk_level: "High", readiness: 38, review_required: true,
  test_summary: { "status" => "failed", "total" => 156, "passed" => 154, "failed" => 2, "new_tests" => 3 },
  files_touched: [
    { "path" => "spec/services/payment_capture_spec.rb", "category" => "test", "additions" => 26, "deletions" => 14 },
    { "path" => "spec/support/redis_isolation.rb", "category" => "test", "additions" => 18, "deletions" => 0 },
    { "path" => "app/services/refund_processor.rb", "category" => "service", "additions" => 6, "deletions" => 2 }
  ],
  missing_checks: [
    { "check" => "2 tests still failing in concurrent refund path", "severity" => "high" },
    { "check" => "Payment-related files modified", "severity" => "high" },
    { "check" => "Race condition in RefundProcessor not root-caused", "severity" => "high" }
  ],
  recommended_actions: [
    { "action" => "Root-cause the RefundProcessor race before merge", "priority" => "high" },
    { "action" => "Re-run suite 10x in parallel to confirm determinism", "priority" => "high" },
    { "action" => "PCI review for refund path change", "priority" => "medium" }
  ],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "fix/flaky-payment-spec", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 20, payload: { prompt: "payment_capture_spec fails intermittently in CI parallel runs. Find and fix the flakiness." } },
    { event_type: "file_read", offset: 50, payload: { file: "spec/services/payment_capture_spec.rb", lines: 210 } },
    { event_type: "command_run", offset: 110, payload: { command: "bundle exec rspec spec/services/payment_capture_spec.rb", exit_code: 0, examples: 21, failures: 0 } },
    { event_type: "command_failed", offset: 200, payload: { command: "PARALLEL_WORKERS=4 bundle exec rspec spec/services/payment_capture_spec.rb", exit_code: 1, examples: 21, failures: 3 } },
    { event_type: "file_edited", offset: 290, payload: { file: "spec/support/redis_isolation.rb", additions: 18, deletions: 0 } },
    { event_type: "file_edited", offset: 360, payload: { file: "spec/services/payment_capture_spec.rb", additions: 26, deletions: 14 } },
    { event_type: "file_edited", offset: 420, payload: { file: "app/services/refund_processor.rb", additions: 6, deletions: 2 } },
    { event_type: "command_failed", offset: 500, payload: { command: "PARALLEL_WORKERS=4 bundle exec rspec", exit_code: 1, examples: 156, failures: 2 } },
    { event_type: "agent_response", offset: 620, payload: { summary: "Redis state isolated per process; capture-window assertions frozen. 2 concurrent-refund failures remain — RefundProcessor race unresolved." } },
    { event_type: "session_completed", offset: 660, payload: { duration_seconds: 660, files_changed: 3 } }
  ]
)

# ── Noise session: helper-process residue, hidden everywhere except
# /runs?status=noise. No workstream, no passport impact. ──
AgentSession.find_or_create_by!(external_session_id: "demo-session-noise-001") do |s|
  s.project = project
  s.workstream = nil
  s.provider = "claude_code"
  s.agent_name = "Claude Code"
  s.branch_name = "rr-553-ai-hardening"
  s.status = "noise"
  s.started_at = 3.hours.ago
  s.completed_at = 3.hours.ago + 40.seconds
  s.metadata = { model: "claude-haiku-4-5-20251001", tokens_used: 900 }
end

# ── Second project: StaffOS Platform gets its own small story so the project
# switcher shows genuinely different data. ──
platform = Project.find_by!(name: "StaffOS Platform")
seed_workstream(
  project: platform, branch_name: "feature/dark-mode",
  title: "Dual-theme design system", description: "Token-level light/dark theming with a persisted topbar toggle.",
  status: "in_review", session_id: "platform-session-001", started_ago: 6.hours.ago, duration_minutes: 14, tokens: 61200,
  intent: "Add a dark theme with a topbar toggle, no flash on first paint",
  summary: "Rebuilt the token layer as themed custom properties resolved at runtime, added a pre-paint boot script reading cookie/localStorage/OS preference, and a Stimulus toggle in the topbar. Both themes verified across all pages.",
  risk_level: "Low", readiness: 91, review_required: false,
  test_summary: { "status" => "passed", "total" => 68, "passed" => 68, "failed" => 0, "new_tests" => 1 },
  files_touched: [
    { "path" => "app/assets/tailwind/application.css", "category" => "other", "additions" => 214, "deletions" => 96 },
    { "path" => "app/javascript/controllers/theme_controller.js", "category" => "other", "additions" => 28, "deletions" => 0 },
    { "path" => "app/views/shared/_head_common.html.erb", "category" => "view", "additions" => 19, "deletions" => 0 },
    { "path" => "app/views/shared/_topbar.html.erb", "category" => "view", "additions" => 8, "deletions" => 4 }
  ],
  missing_checks: [],
  recommended_actions: [{ "action" => "Spot-check charts and rings on dark once real data lands", "priority" => "low" }],
  events_data: [
    { event_type: "session_started", offset: 0, payload: { branch: "feature/dark-mode", model: "claude-sonnet-4-20250514" } },
    { event_type: "prompt_submitted", offset: 15, payload: { prompt: "Add a dark theme with a topbar toggle. No flash of the wrong theme on first paint." } },
    { event_type: "file_read", offset: 40, payload: { file: "app/assets/tailwind/application.css", lines: 257 } },
    { event_type: "file_edited", offset: 200, payload: { file: "app/assets/tailwind/application.css", additions: 214, deletions: 96 } },
    { event_type: "file_edited", offset: 380, payload: { file: "app/javascript/controllers/theme_controller.js", additions: 28, deletions: 0 } },
    { event_type: "file_edited", offset: 470, payload: { file: "app/views/shared/_head_common.html.erb", additions: 19, deletions: 0 } },
    { event_type: "file_edited", offset: 540, payload: { file: "app/views/shared/_topbar.html.erb", additions: 8, deletions: 4 } },
    { event_type: "command_run", offset: 600, payload: { command: "bin/rails tailwindcss:build && bin/rails test", exit_code: 0, examples: 68, failures: 0 } },
    { event_type: "agent_response", offset: 780, payload: { summary: "Dual-theme token system live: runtime vars, boot script, persisted toggle. All tests green." } },
    { event_type: "session_completed", offset: 840, payload: { duration_seconds: 840, files_changed: 4 } }
  ],
  run_council: true
)

puts "Seeded: #{Project.count} projects, #{Workstream.count} workstreams, #{AgentSession.count} sessions (#{AgentSession.where(status: 'active').count} active, #{AgentSession.where(status: 'noise').count} noise), #{RunEvent.count} events, #{RunPassport.count} passports, #{PassportVersion.count} versions, #{CouncilReview.count} council reviews, #{Document.count} documents, #{DecisionLog.count} decisions, #{MemoryItem.count} memory items"
