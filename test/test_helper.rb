ENV["RAILS_ENV"] ||= "test"

# Measure coverage of our own code (app/ and lib/) — start before anything is
# required so every load is tracked. Opt out with COVERAGE=false.
unless ENV["COVERAGE"] == "false"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    skip "/test/"
    skip "/config/"
    group "Services", "app/services"
  end
end

require_relative "../config/environment"
require "rails/test_help"

class ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def sign_in_user(email: "dev@staffos.test", password: "password123")
    user = User.create!(email: email, password: password, password_confirmation: password)
    sign_in user
    user
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Rails only forks workers once the suite exceeds its size threshold; each
    # forked worker must report into SimpleCov separately or the merged
    # coverage silently comes out as 0%.
    parallelize_setup do |worker|
      SimpleCov.command_name "#{SimpleCov.command_name}-#{worker}" if defined?(SimpleCov)
    end

    parallelize_teardown do
      SimpleCov.result if defined?(SimpleCov)
    end

    # Force the deterministic-heuristic path by disabling the LLM client for the
    # duration of the block, regardless of any configured key/credentials.
    # Stubs the key source itself: instances resolve their key via
    # LlmClient.api_key / key_for at initialize, so nilling the class-level key
    # (with no per-user keys in tests) guarantees every instance is disabled.
    def without_llm
      original = LlmClient.method(:api_key)
      LlmClient.define_singleton_method(:api_key) { nil }
      yield
    ensure
      LlmClient.define_singleton_method(:api_key, original)
    end

    # Builders for the StaffOS domain graph. Tests construct records directly
    # rather than via fixtures so the relationships (project → workstream →
    # session → events → passport) stay explicit and easy to read.
    def make_project(name: "Test Project", repo_name: "test/repo", user: nil, **attrs)
      user ||= User.first || User.create!(email: "owner-#{SecureRandom.hex(4)}@test.dev", password: "password123")
      Project.create!(name: name, repo_name: repo_name, user: user, **attrs)
    end

    def make_workstream(project: make_project, branch_name: "feature/test", **attrs)
      Workstream.find_or_create_for_branch(project: project, branch_name: branch_name).tap do |ws|
        ws.update!(attrs) if attrs.any?
      end
    end

    def make_session(project: make_project, workstream: nil, **attrs)
      AgentSession.create!(
        project: project,
        workstream: workstream,
        external_session_id: "sess-#{SecureRandom.hex(4)}",
        provider: "claude_code",
        agent_name: "Claude Code",
        branch_name: workstream&.branch_name || "feature/test",
        status: "active",
        started_at: Time.current,
        **attrs
      )
    end

    # Builds a passport directly with a known files_touched payload, bypassing
    # the event pipeline — handy for risk/council/document tests. Passports are
    # per-workstream (one each, DB-enforced); when none is given, a fresh
    # workstream with one session is created so callers can reach a session via
    # passport.agent_sessions.
    def make_passport(files_touched: [], test_summary: {}, intent: "Do a thing", workstream: nil, **attrs)
      unless workstream
        workstream = make_workstream(branch_name: "feature/passport-#{SecureRandom.hex(4)}")
        make_session(project: workstream.project, workstream: workstream)
      end
      RunPassport.create!(
        workstream: workstream,
        intent: intent,
        summary: "A summary",
        risk_level: "Low",
        readiness_score: 80,
        human_review_required: false,
        files_touched: files_touched,
        test_summary: test_summary,
        missing_checks: [],
        recommended_actions: [],
        **attrs
      )
    end
  end
end
