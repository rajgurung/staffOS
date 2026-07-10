# This seed file is DEMO DATA for local development only — it creates users with
# well-known passwords and fake projects. It must never run against production.
# Skip gracefully (not abort) so `db:prepare` on a fresh prod DB still succeeds.
unless Rails.env.development?
  puts "Skipping db/seeds.rb: development-only demo data (current env: #{Rails.env})."
  return
end

# Default users
owner = User.find_or_create_by!(email: "raj@staffos.dev") { |u| u.name = "Raj Gurung"; u.password = "password123"; u.password_confirmation = "password123" }
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

ApiToken.find_or_create_by!(name: "CLI Token") { |t| t.project = project }

# Helper to seed a workstream with session, events, passport, and version
def seed_workstream(project:, branch_name:, title:, description:, status:, merged_at: nil,
                    session_id:, started_ago:, duration_minutes:, model: "claude-sonnet-4-20250514", tokens:,
                    intent:, summary:, risk_level:, readiness:, review_required:, review_mode: "passive",
                    test_summary:, files_touched:, missing_checks:, recommended_actions:, events_data:,
                    run_council: false)
  ws = Workstream.find_or_create_for_branch(project: project, branch_name: branch_name)
  ws.update!(title: title, description: description, status: status, merged_at: merged_at)

  session = AgentSession.find_or_create_by!(external_session_id: session_id) do |s|
    s.project = project
    s.workstream = ws
    s.provider = "claude_code"
    s.agent_name = "Claude Code"
    s.branch_name = branch_name
    s.status = "completed"
    s.started_at = started_ago
    s.completed_at = started_ago + duration_minutes.minutes
    s.metadata = { model: model, tokens_used: tokens }
  end

  base = session.started_at
  events_data.each do |ed|
    RunEvent.find_or_create_by!(agent_session: session, event_type: ed[:event_type], occurred_at: base + ed[:offset].seconds) do |e|
      e.payload = ed[:payload]
      e.source = "claude_code"
      e.workstream = ws
    end
  end

  passport = RunPassport.find_or_create_by!(agent_session: session) do |p|
    p.workstream = ws
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

  passport.create_version!(trigger: "session_completed") if passport.passport_versions.empty?

  if run_council
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
  run_council: true
)

# ── Workstream 2: OAuth token refresh ──
seed_workstream(
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
seed_workstream(
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

puts "Seeded: #{Project.count} projects, #{Workstream.count} workstreams, #{AgentSession.count} sessions, #{RunEvent.count} events, #{RunPassport.count} passports, #{PassportVersion.count} versions, #{CouncilReview.count} council reviews, #{Document.count} documents, #{DecisionLog.count} decisions, #{MemoryItem.count} memory items"
