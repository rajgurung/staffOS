require "test_helper"

class PassportGeneratorTest < ActiveSupport::TestCase
  def setup
    @session = make_session
    add_event("prompt_submitted", prompt: "Refactor the retry handler")
    add_event("file_edited", file: "app/services/retry_handler.rb", additions: 40, deletions: 5)
    add_event("file_edited", file: "spec/services/retry_handler_spec.rb", additions: 20, deletions: 0)
    add_event("command_run", command: "bundle exec rspec", exit_code: 0, examples: 12, failures: 0)
  end

  test "generate! builds a passport from the event stream" do
    passport = PassportGenerator.new(@session).generate!

    assert_equal "Refactor the retry handler", passport.intent
    assert_equal 2, passport.files_touched.size
    assert_equal "passed", passport.test_summary["status"]
    assert_includes %w[Low Medium High], passport.risk_level
    assert_equal "heuristic", passport.summary_source
  end

  test "generate! is idempotent for a session" do
    first = PassportGenerator.new(@session).generate!
    second = PassportGenerator.new(@session).generate!
    assert_equal first.id, second.id
  end

  test "apply_smart_summary! falls back to heuristics without an API key" do
    passport = PassportGenerator.new(@session).generate!
    without_llm do
      used_llm = PassportGenerator.new(@session).apply_smart_summary!(passport)
      assert_not used_llm
      assert_equal "heuristic", passport.reload.summary_source
      assert_equal 0, passport.cost_cents
    end
  end

  private

  def add_event(type, **payload)
    @session.run_events.create!(event_type: type, occurred_at: Time.current, payload: payload)
  end
end
