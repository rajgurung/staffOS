require "test_helper"

class PassportGeneratorTest < ActiveSupport::TestCase
  def setup
    @workstream = make_workstream(branch_name: "feature/retry-handler")
    @session = make_session(project: @workstream.project, workstream: @workstream)
    add_event("prompt_submitted", prompt: "Refactor the retry handler")
    add_event("file_edited", file: "app/services/retry_handler.rb", additions: 40, deletions: 5)
    add_event("file_edited", file: "spec/services/retry_handler_spec.rb", additions: 20, deletions: 0)
    add_event("command_run", command: "bundle exec rspec", exit_code: 0, examples: 12, failures: 0)
  end

  test "generate! builds a passport from the workstream's event stream" do
    passport = PassportGenerator.new(@workstream).generate!

    assert_equal @workstream, passport.workstream
    assert_equal "Refactor the retry handler", passport.intent
    assert_equal 2, passport.files_touched.size
    assert_equal "passed", passport.test_summary["status"]
    assert_includes %w[Low Medium High], passport.risk_level
    assert_equal "heuristic", passport.summary_source
  end

  test "generate! upserts the same passport per workstream" do
    first = PassportGenerator.new(@workstream).generate!
    second = PassportGenerator.new(@workstream).generate!
    assert_equal first.id, second.id
    assert_equal 1, RunPassport.where(workstream: @workstream).count
  end

  test "events from multiple sessions accumulate into one assessment" do
    second_session = make_session(project: @workstream.project, workstream: @workstream)
    add_event("file_edited", session: second_session, file: "app/models/widget.rb", additions: 10, deletions: 0)

    passport = PassportGenerator.new(@workstream).generate!

    paths = passport.files_touched.map { |f| f["path"] }
    assert_includes paths, "app/services/retry_handler.rb"
    assert_includes paths, "app/models/widget.rb"
  end

  test "eternal branches assess only the rolling window" do
    ws = make_workstream(branch_name: "main")
    session = make_session(project: ws.project, workstream: ws)
    add_event("file_edited", workstream: ws, session: session, occurred_at: 8.days.ago,
              file: "app/models/old.rb", additions: 5, deletions: 1)
    add_event("file_edited", workstream: ws, session: session, occurred_at: 1.hour.ago,
              file: "app/models/recent.rb", additions: 5, deletions: 1)

    passport = PassportGenerator.new(ws).generate!

    paths = passport.files_touched.map { |f| f["path"] }
    assert_includes paths, "app/models/recent.rb"
    assert_not_includes paths, "app/models/old.rb"
  end

  test "feature branches assess all events regardless of age" do
    ws = make_workstream(branch_name: "feature/x")
    session = make_session(project: ws.project, workstream: ws)
    add_event("file_edited", workstream: ws, session: session, occurred_at: 8.days.ago,
              file: "app/models/old.rb", additions: 5, deletions: 1)
    add_event("file_edited", workstream: ws, session: session, occurred_at: 1.hour.ago,
              file: "app/models/recent.rb", additions: 5, deletions: 1)

    passport = PassportGenerator.new(ws).generate!

    paths = passport.files_touched.map { |f| f["path"] }
    assert_includes paths, "app/models/old.rb"
    assert_includes paths, "app/models/recent.rb"
  end

  test "generate! preserves LLM enrichment across subsequent session stops" do
    passport = PassportGenerator.new(@workstream).generate!
    passport.update!(
      intent: "LLM-written intent",
      summary: "LLM-written summary",
      summary_source: "llm",
      missing_checks: (passport.missing_checks || []) +
        [{ "check" => "Add idempotency spec", "severity" => "medium", "source" => "llm" }]
    )

    second_session = make_session(project: @workstream.project, workstream: @workstream)
    add_event("file_edited", session: second_session, file: "app/models/widget.rb", additions: 10, deletions: 0)
    rebuilt = PassportGenerator.new(@workstream).generate!

    assert_equal "LLM-written intent", rebuilt.intent
    assert_equal "LLM-written summary", rebuilt.summary
    assert_equal "llm", rebuilt.summary_source
    assert_includes rebuilt.missing_checks.map { |c| c["check"] }, "Add idempotency spec"
    assert_includes rebuilt.files_touched.map { |f| f["path"] }, "app/models/widget.rb",
      "deterministic fields must still refresh"
  end

  test "apply_smart_summary! falls back to heuristics without an API key" do
    passport = PassportGenerator.new(@workstream).generate!
    without_llm do
      used_llm = PassportGenerator.new(@workstream).apply_smart_summary!(passport)
      assert_not used_llm
      assert_equal "heuristic", passport.reload.summary_source
      assert_equal 0, passport.cost_cents
    end
  end

  private

  def add_event(type, workstream: @workstream, session: @session, occurred_at: Time.current, **payload)
    session.run_events.create!(event_type: type, occurred_at: occurred_at,
                               workstream: workstream, payload: payload)
  end
end
