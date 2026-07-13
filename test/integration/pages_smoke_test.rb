require "test_helper"

# Smoke test: every primary page renders for a signed-in user with real data in
# the current project. Catches view/controller regressions across the app.
class PagesSmokeTest < ActionDispatch::IntegrationTest
  def setup
    sign_in_user
    @passport = make_passport(
      files_touched: [{ "path" => "app/services/x.rb", "additions" => 10, "deletions" => 1, "category" => "service" }],
      intent: "Do work", summary: "Did work"
    )
    @project = @passport.project
    @document = Document.create!(project: @project, run_passport: @passport, document_type: "adr", title: "An ADR", content_markdown: "# ADR")
    @decision = DecisionLog.create!(project: @project, run_passport: @passport, title: "A decision", decision: "We chose X", status: "active")
    MemoryItem.create!(project: @project, memory_type: "decision", content: "Remember X", confidence: 0.8)
  end

  test "index and detail pages render" do
    [
      dashboard_path,
      risk_cockpit_path,
      settings_path,
      workstreams_path,
      workstream_path(@passport.workstream),
      runs_path,
      run_passports_path,
      documents_path,
      document_path(@document),
      decision_logs_path,
      decision_log_path(@decision),
      memory_items_path,
      projects_path,
      project_path(@project),
      search_path(q: "work")
    ].each do |path|
      get path
      assert_response :success, "expected 200 for #{path}, got #{response.status}"
    end
  end
end
