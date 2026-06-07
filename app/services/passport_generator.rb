class PassportGenerator
  def initialize(agent_session)
    @session = agent_session
    @events = agent_session.run_events.order(occurred_at: :asc)
  end

  def generate!
    return @session.run_passport if @session.run_passport.present?

    passport = @session.build_run_passport(
      intent: extract_intent,
      summary: build_summary,
      risk_level: "Pending",
      readiness_score: 0,
      human_review_required: false,
      test_summary: extract_test_summary,
      files_touched: extract_files_touched,
      missing_checks: [],
      recommended_actions: []
    )

    passport.save!

    score = RiskScorer.new(passport).score
    passport.update!(
      risk_level: score[:level],
      human_review_required: score[:human_review_required],
      readiness_score: calculate_readiness(passport, score),
      missing_checks: generate_missing_checks(passport, score),
      recommended_actions: generate_recommendations(passport, score)
    )

    passport
  end

  private

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

    parts.join(". ").presence || "Session completed"
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

  def calculate_readiness(passport, score)
    base = 100
    base -= 15 if score[:level] == "High"
    base -= 8 if score[:level] == "Medium"

    test_summary = passport.test_summary || {}
    base -= 20 if test_summary.empty?
    base -= 25 if test_summary["status"] == "failed"

    base -= 5 if passport.files_touched&.none? { |f| f["category"] == "test" }

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

    actions << { "action" => "Generate PR summary from passport", "priority" => "low" }
    actions
  end
end
