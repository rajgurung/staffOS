class PassportGenerator
  # Eternal branches never merge, so their passport assesses a rolling window
  # instead of blending months of unrelated work. Event history is never
  # trimmed — the window only bounds what the assessment reads.
  ETERNAL_BRANCHES = %w[main master].freeze
  ROLLING_WINDOW = 7.days

  def initialize(workstream)
    @workstream = workstream
    scope = workstream.run_events.order(occurred_at: :asc)
    scope = scope.where(occurred_at: ROLLING_WINDOW.ago..) if ETERNAL_BRANCHES.include?(workstream.branch_name)
    @events = scope
  end

  # Full rebuild of the workstream's living passport from all its (windowed)
  # events. Upserts in place — never delete/recreate — so council reviews,
  # documents, and version history survive every reassessment. Deterministic
  # fields (risk, readiness, files, tests, checks) always refresh; narrative
  # fields written by the LLM (intent, summary) and LLM-sourced checks are
  # preserved — paid-for enrichment must survive later session stops.
  def generate!
    passport = @workstream.run_passport || @workstream.build_run_passport
    llm_enriched = passport.persisted? && passport.summary_source == "llm"
    carried_checks = llm_enriched ? Array(passport.missing_checks).select { |c| c["source"] == "llm" } : []

    files_touched = extract_files_touched
    attrs = {
      risk_level: "Pending",
      readiness_score: 0,
      human_review_required: false,
      test_summary: extract_test_summary,
      files_touched: files_touched,
      branch_coverage: compute_branch_coverage(files_touched),
      missing_checks: [],
      recommended_actions: []
    }
    unless llm_enriched
      attrs[:intent] = extract_intent
      attrs[:summary] = build_summary
      attrs[:summary_source] = "heuristic"
    end
    passport.assign_attributes(attrs)
    passport.save!

    score = RiskScorer.new(passport).score
    passport.update!(
      risk_level: score[:level],
      human_review_required: score[:human_review_required] || coverage_gap_dominates?(passport),
      readiness_score: calculate_readiness(passport, score),
      missing_checks: (generate_missing_checks(passport, score) + carried_checks).uniq { |c| c["check"] },
      recommended_actions: generate_recommendations(passport, score)
    )

    passport
  rescue ActiveRecord::RecordNotUnique
    # Two sessions stopping on the same branch at once can both build a fresh
    # passport; the unique index makes the loser retry against the winner's row.
    raise if @upsert_retried
    @upsert_retried = true
    @workstream.reload_run_passport
    retry
  end

  # Smart-summary mode (SPEC §16): use a cheaper model to summarise the session
  # and extract risks. Risk *level* stays deterministic (SPEC §15) — the LLM
  # enriches the narrative summary, intent, and missing checks only. Returns
  # true when the LLM was actually used, false when it fell back to heuristics.
  def apply_smart_summary!(passport)
    client = LlmClient.new(model: LlmClient::SUMMARY_MODEL)
    return false unless client.enabled?

    result = client.complete(
      system: smart_summary_system,
      prompt: smart_summary_prompt(passport),
      max_tokens: 1500,
      schema: smart_summary_schema
    )
    data = result&.text
    return false unless data.is_a?(Hash)

    # Tag LLM-found checks so generate! can carry them across rebuilds.
    llm_checks = Array(data["additional_checks"]).map { |c| c.merge("source" => "llm") }
    merged_checks = (passport.missing_checks || []) + llm_checks
    passport.update!(
      intent: data["intent"].presence || passport.intent,
      summary: data["summary"].presence || passport.summary,
      missing_checks: merged_checks.uniq { |c| c["check"] },
      summary_source: "llm",
      input_tokens: passport.input_tokens + result.input_tokens,
      output_tokens: passport.output_tokens + result.output_tokens,
      cost_cents: passport.cost_cents + result.cost_cents
    )
    true
  end

  private

  def smart_summary_system
    <<~SYS
      You are StaffOS, a reviewer that turns AI-assisted coding work into a
      verified engineering record. You receive only metadata about the work on
      one git branch — file paths, change sizes, categories, test results, and
      risk signals, accumulated across the captured sessions on that branch.
      You never see source code. Be precise, concrete, and concise. Write for a
      senior engineer reviewing the branch before merge.
    SYS
  end

  def smart_summary_prompt(passport)
    <<~PROMPT
      Summarise the AI-assisted work on this branch (#{passport.agent_sessions.count} captured sessions) and extract review gaps.

      Stated intent (raw prompt): #{passport.intent}
      Branch: #{passport.workstream.branch_name}
      Deterministic risk level (do not contradict): #{passport.risk_level}

      Files touched:
      #{files_for_prompt(passport)}

      Test evidence: #{passport.test_summary.presence || 'none captured'}

      Existing deterministic missing checks:
      #{(passport.missing_checks || []).map { |c| "- #{c['check']}" }.join("\n").presence || '- none'}

      Return a tight 1-3 sentence intent, a 2-4 sentence summary of what changed
      and why it matters, and any ADDITIONAL review gaps not already listed.
    PROMPT
  end

  def smart_summary_schema
    {
      type: "object",
      additionalProperties: false,
      properties: {
        intent: { type: "string" },
        summary: { type: "string" },
        additional_checks: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              check: { type: "string" },
              severity: { type: "string", enum: %w[low medium high] }
            },
            required: %w[check severity]
          }
        }
      },
      required: %w[intent summary additional_checks]
    }
  end

  def files_for_prompt(passport)
    files = passport.files_touched || []
    return "- none" if files.empty?
    files.map { |f| "- #{f['path']} (#{f['category']}, +#{f['additions']}/-#{f['deletions']})" }.join("\n")
  end

  def extract_intent
    prompt_event = @events.find_by(event_type: "prompt_submitted")
    prompt_event&.payload&.dig("prompt") || "No intent captured"
  end

  def build_summary
    file_events = @events.where(event_type: %w[file_edited file_read])
    command_events = @events.where(event_type: "command_run")
    response_event = @events.find_by(event_type: "agent_response")

    if response_event&.payload&.dig("summary")
      return response_event.payload["summary"]
    end

    parts = []
    edited_files = file_events.where(event_type: "file_edited").map { |e| e.payload["file"] }.compact.uniq
    parts << "Modified #{edited_files.count} files: #{edited_files.join(', ')}" if edited_files.any?

    commands = command_events.map { |e| e.payload["command"] }.compact
    parts << "Ran #{commands.count} commands" if commands.any?

    parts.join(". ").presence || "No captured activity in the assessed window"
  end

  def extract_test_summary
    test_events = @events.where(event_type: "command_run").select { |e|
      cmd = e.payload["command"].to_s
      cmd.match?(/rspec|test|jest|pytest|mocha|vitest/i)
    }

    return {} if test_events.empty?

    last_test = test_events.last
    {
      "status" => last_test.payload["exit_code"].to_i == 0 ? "passed" : "failed",
      "total" => last_test.payload["examples"].to_i,
      "passed" => last_test.payload["examples"].to_i - last_test.payload["failures"].to_i,
      "failed" => last_test.payload["failures"].to_i
    }
  end

  def extract_files_touched
    file_events = @events.where(event_type: %w[file_read file_edited])
    files = {}

    file_events.each do |event|
      path = event.payload["file"]
      next unless path
      files[path] ||= { "path" => path, "additions" => 0, "deletions" => 0, "category" => categorize_file(path) }
      if event.event_type == "file_edited"
        files[path]["additions"] += event.payload["additions"].to_i
        files[path]["deletions"] += event.payload["deletions"].to_i
      end
    end

    files.values
  end

  def categorize_file(path)
    case path
    when /spec|test/i then "test"
    when /controller/i then "controller"
    when /model/i then "model"
    when /service/i then "service"
    when /config|initializer/i then "config"
    when /migration/i then "migration"
    when /view|template/i then "view"
    else "other"
    end
  end

  # The branch's real state (from the CLI's git snapshot) vs what the captured
  # sessions touched. Paths from tool events are absolute while git's are
  # repo-relative, so observation is matched by suffix. Nil when no snapshot
  # exists or on eternal branches (a branch diffed against itself is empty).
  def compute_branch_coverage(files_touched)
    return nil if ETERNAL_BRANCHES.include?(@workstream.branch_name)

    snapshot = @workstream.run_events.where(event_type: "branch_snapshot").order(occurred_at: :desc).first
    return nil unless snapshot

    branch_paths = Array(snapshot.payload["files"]).filter_map { |f| f["path"].presence }
    return nil if branch_paths.empty?

    observed_paths = files_touched.map { |f| f["path"] }
    unobserved = branch_paths.reject do |bp|
      observed_paths.any? { |op| op == bp || op.end_with?("/#{bp}") }
    end

    {
      "base_branch" => snapshot.payload["base_branch"],
      "branch_files" => branch_paths.size,
      "observed" => branch_paths.size - unobserved.size,
      "unobserved_paths" => unobserved
    }
  end

  def coverage_gap_dominates?(passport)
    coverage = passport.branch_coverage
    return false unless coverage && coverage["unobserved_paths"].present?
    coverage["unobserved_paths"].size > coverage["observed"].to_i
  end

  def calculate_readiness(passport, score)
    base = 100
    base -= 15 if score[:level] == "High"
    base -= 8 if score[:level] == "Medium"

    test_summary = passport.test_summary || {}
    base -= 20 if test_summary.empty?
    base -= 25 if test_summary["status"] == "failed"

    base -= 5 if passport.files_touched&.none? { |f| f["category"] == "test" }

    if passport.branch_coverage && passport.branch_coverage["unobserved_paths"].present?
      base -= coverage_gap_dominates?(passport) ? 20 : 10
    end

    [base, 0].max
  end

  def generate_missing_checks(passport, score)
    checks = []
    test_summary = passport.test_summary || {}

    if test_summary.empty?
      checks << { "check" => "No test evidence found", "severity" => "high" }
    end

    if passport.files_touched&.none? { |f| f["category"] == "test" }
      checks << { "check" => "No test files modified alongside code changes", "severity" => "medium" }
    end

    score[:signals].select { |s| s[:risk] == "high" }.each do |signal|
      checks << { "check" => signal[:reason], "severity" => "high" }
    end

    coverage = passport.branch_coverage
    if coverage && (unobserved = coverage["unobserved_paths"]).present?
      listed = unobserved.first(5).join(", ")
      listed += ", …" if unobserved.size > 5
      checks << {
        "check" => "#{unobserved.size} #{"file".pluralize(unobserved.size)} changed on branch without captured session activity: #{listed}",
        "severity" => coverage_gap_dominates?(passport) ? "high" : "medium"
      }
    end

    checks
  end

  def generate_recommendations(passport, score)
    actions = []

    if score[:level] != "Low"
      actions << { "action" => "Review risk signals before merging", "priority" => "high" }
    end

    if (passport.test_summary || {}).empty?
      actions << { "action" => "Run test suite and capture results", "priority" => "high" }
    end

    if passport.files_touched&.any? { |f| f["category"] == "config" }
      actions << { "action" => "Verify configuration change in staging", "priority" => "medium" }
    end

    if passport.branch_coverage && passport.branch_coverage["unobserved_paths"].present?
      actions << { "action" => "Manually review branch changes no session touched", "priority" => "high" }
    end

    actions << { "action" => "Generate PR summary from passport", "priority" => "low" }
    actions
  end
end
