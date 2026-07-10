ENV["RAILS_ENV"] ||= "test"

# Measure coverage of our own code (app/ and lib/) — start before anything is
# required so every load is tracked. Opt out with COVERAGE=false.
unless ENV["COVERAGE"] == "false"
  require "simplecov"
  SimpleCov.start "rails" do
    enable_coverage :branch
    add_filter "/test/"
    add_filter "/config/"
    add_group "Services", "app/services"
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

    # Force the deterministic-heuristic path by disabling the LLM client for the
    # duration of the block, regardless of any configured key/credentials.
    def without_llm
      original = LlmClient.method(:enabled?)
      LlmClient.define_singleton_method(:enabled?) { false }
      yield
    ensure
      LlmClient.define_singleton_method(:enabled?, original)
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
    # the event pipeline — handy for risk/council/document tests.
    def make_passport(files_touched: [], test_summary: {}, intent: "Do a thing", **attrs)
      session = make_session
      session.create_run_passport!(
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
