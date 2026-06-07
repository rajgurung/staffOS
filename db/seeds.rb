# Default user
User.find_or_create_by!(email: "raj@staffos.dev") do |u|
  u.name = "Raj Rathod"
  u.password = "password123"
  u.password_confirmation = "password123"
end

project = Project.find_or_create_by!(name: "AI Peer Review Pipeline") do |p|
  p.repo_name = "staffos/ai-peer-review"
  p.tech_stack = "Ruby on Rails, PostgreSQL, Sidekiq, RSpec"
  p.risk_rules = {
    "auth_files" => "high",
    "payment_files" => "high",
    "infra_files" => "high",
    "no_tests" => "warning",
    "retry_logic" => "medium"
  }
end

session = AgentSession.find_or_create_by!(external_session_id: "demo-session-001") do |s|
  s.project = project
  s.provider = "claude_code"
  s.agent_name = "Claude Code"
  s.branch_name = "rr-553-ai-hardening"
  s.status = "completed"
  s.started_at = 2.hours.ago
  s.completed_at = 1.hour.ago
  s.metadata = { model: "claude-sonnet-4-20250514", tokens_used: 48200 }
end

base_time = 2.hours.ago

events_data = [
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
]

events_data.each do |ed|
  RunEvent.find_or_create_by!(
    agent_session: session,
    event_type: ed[:event_type],
    occurred_at: base_time + ed[:offset].seconds
  ) do |e|
    e.payload = ed[:payload]
    e.source = "claude_code"
  end
end

RunPassport.find_or_create_by!(agent_session: session) do |p|
  p.intent = "Review and harden the inference callback retry path. Check tests and observability."
  p.summary = "Refactored inference callback handler with exponential backoff retry logic, added idempotency key validation to prevent duplicate processing, and improved structured logging with correlation IDs across the callback pipeline. All existing tests pass, 12 new test cases added covering retry edge cases and idempotency scenarios."
  p.risk_level = "Medium"
  p.readiness_score = 72
  p.human_review_required = true
  p.test_summary = {
    "status" => "passed",
    "total" => 142,
    "passed" => 142,
    "failed" => 0,
    "pending" => 0,
    "new_tests" => 12,
    "coverage" => 87.3
  }
  p.files_touched = [
    { "path" => "app/services/inference_callback_handler.rb", "category" => "service", "additions" => 42, "deletions" => 11 },
    { "path" => "spec/services/inference_callback_handler_spec.rb", "category" => "test", "additions" => 45, "deletions" => 3 },
    { "path" => "app/services/ai_provider_client.rb", "category" => "service", "additions" => 0, "deletions" => 0 },
    { "path" => "config/initializers/retry_config.rb", "category" => "config", "additions" => 8, "deletions" => 0 },
    { "path" => "app/controllers/api/v1/callbacks_controller.rb", "category" => "controller", "additions" => 0, "deletions" => 0 },
    { "path" => "app/services/callback_logger.rb", "category" => "service", "additions" => 18, "deletions" => 5 },
    { "path" => "app/services/inference_callback_handler.rb", "category" => "service", "additions" => 6, "deletions" => 1 }
  ]
  p.missing_checks = [
    { "check" => "Idempotency edge case test for concurrent callbacks", "severity" => "high" },
    { "check" => "Correlation ID propagation to downstream services", "severity" => "medium" },
    { "check" => "Retry behaviour not captured in an ADR", "severity" => "medium" },
    { "check" => "Lint check not run", "severity" => "low" }
  ]
  p.recommended_actions = [
    { "action" => "Add idempotency spec for concurrent callback scenario", "priority" => "high" },
    { "action" => "Add correlation ID to structured logs", "priority" => "high" },
    { "action" => "Save retry behaviour as ADR", "priority" => "medium" },
    { "action" => "Add PR note explaining failure path", "priority" => "medium" },
    { "action" => "Run linter before merge", "priority" => "low" }
  ]
end

passport = RunPassport.first

# Documents
Document.find_or_create_by!(title: "ADR: Exponential Backoff Retry Strategy") do |d|
  d.project = project
  d.run_passport = passport
  d.document_type = "adr"
  d.status = "published"
  d.content_markdown = <<~MD
    # ADR: Exponential Backoff Retry Strategy

    ## Status
    Accepted

    ## Context
    The inference callback handler was using a fixed retry count of 3 with no backoff.
    Under load, this caused thundering herd problems when the AI provider returned transient errors.

    ## Decision
    Implement exponential backoff with jitter for all inference callback retries.
    Maximum 5 attempts with a base delay of 1 second and max delay of 30 seconds.

    ## Consequences
    - Reduced load on AI providers during transient failures
    - Slightly increased latency for retried requests
    - Need to monitor retry metrics in New Relic
  MD
end

Document.find_or_create_by!(title: "PR Summary: Harden inference callback retry path") do |d|
  d.project = project
  d.run_passport = passport
  d.document_type = "pr_summary"
  d.status = "published"
  d.content_markdown = <<~MD
    ## Summary
    - Replace fixed retry with exponential backoff (max 5 attempts)
    - Add idempotency key check to prevent duplicate callback processing
    - Add correlation ID to structured logs across callback pipeline
    - 12 new test cases covering retry edge cases

    ## Test Plan
    - [x] Existing RSpec suite passes (142 examples, 0 failures)
    - [x] New idempotency tests cover concurrent callback scenarios
    - [ ] Manual verification of retry behaviour under load
    - [ ] Verify correlation IDs appear in New Relic traces
  MD
end

# Decision Logs
DecisionLog.find_or_create_by!(title: "Retry failed inference callbacks on empty/malformed responses") do |d|
  d.project = project
  d.run_passport = passport
  d.status = "active"
  d.context = "AI inference providers occasionally return empty or malformed responses during high load. The previous implementation treated these as permanent failures."
  d.decision = "Automatically retry failed inference callbacks when provider response is empty or malformed, using exponential backoff with a maximum of 5 attempts."
  d.rationale = "Transient failures from AI providers are common and recoverable. A fixed retry without backoff was causing thundering herd issues. Exponential backoff with jitter distributes retry load more evenly."
  d.consequences = "Increased resilience to transient AI provider failures. Slightly higher latency for failed requests. Need monitoring to detect when retries are exhausted."
end

DecisionLog.find_or_create_by!(title: "Require idempotency keys for all callback endpoints") do |d|
  d.project = project
  d.run_passport = passport
  d.status = "active"
  d.context = "Duplicate callbacks were observed in production when AI providers retry delivery after network timeouts."
  d.decision = "Require idempotency keys on all callback endpoints. Process each key exactly once using a Redis-backed deduplication check."
  d.rationale = "Without idempotency, duplicate callbacks caused duplicate work items and incorrect billing calculations."
  d.consequences = "All callback producers must include an idempotency key. Redis dependency added for deduplication. Keys expire after 24 hours."
end

# Memory Items
MemoryItem.find_or_create_by!(content: "Inference callbacks now require idempotency keys for all providers.") do |m|
  m.project = project
  m.memory_type = "decision"
  m.confidence = 0.95
end

MemoryItem.find_or_create_by!(content: "Service orchestration is preferred over model callbacks for AI workflow coordination.") do |m|
  m.project = project
  m.memory_type = "convention"
  m.confidence = 0.9
end

MemoryItem.find_or_create_by!(content: "All external callbacks need idempotency protection. Retry behaviour must have tests.") do |m|
  m.project = project
  m.memory_type = "constraint"
  m.confidence = 1.0
end

MemoryItem.find_or_create_by!(content: "AI workflow logs need correlation ID for tracing across service boundaries.") do |m|
  m.project = project
  m.memory_type = "pattern"
  m.confidence = 0.85
end

# API Token
ApiToken.find_or_create_by!(name: "CLI Token") do |t|
  t.project = project
end

puts "Seeded: #{Project.count} projects, #{AgentSession.count} sessions, #{RunEvent.count} events, #{RunPassport.count} passports, #{Document.count} documents, #{DecisionLog.count} decisions, #{MemoryItem.count} memory items"
