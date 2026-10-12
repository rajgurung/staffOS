require "test_helper"

class RiskScorerTest < ActiveSupport::TestCase
  def file(path, additions: 10, deletions: 0)
    { "path" => path, "additions" => additions, "deletions" => deletions, "category" => "other" }
  end

  test "auth-sensitive files are scored High risk" do
    passport = make_passport(
      files_touched: [file("app/controllers/sessions_controller.rb")],
      test_summary: { "status" => "passed", "failed" => 0 }
    )
    result = RiskScorer.new(passport).score
    assert_equal "High", result[:level]
    assert result[:human_review_required]
  end

  test "service-layer changes with tests are Medium risk" do
    passport = make_passport(
      files_touched: [
        file("app/services/retry_worker.rb"),
        file("spec/services/retry_worker_spec.rb")
      ],
      test_summary: { "status" => "passed", "failed" => 0 }
    )
    assert_equal "Medium", RiskScorer.new(passport).score[:level]
  end

  test "documentation-only change with no risky files and passing tests is Low risk" do
    passport = make_passport(
      files_touched: [file("README.md"), file("docs/guide.md")],
      test_summary: { "status" => "passed", "failed" => 0 }
    )
    result = RiskScorer.new(passport).score
    assert_equal "Low", result[:level]
    assert_not result[:human_review_required]
  end

  test "missing test evidence raises a high-risk signal" do
    passport = make_passport(files_touched: [file("app/models/widget.rb")], test_summary: {})
    result = RiskScorer.new(passport).score
    assert_equal "High", result[:level]
    assert(result[:signals].any? { |s| s[:check] == "tests_not_run" })
  end

  test "numeric score is bounded at 10" do
    passport = make_passport(
      files_touched: [file("config/credentials.yml"), file("db/migrate/x.rb"), file(".github/workflows/ci.yml")],
      test_summary: {}
    )
    assert_operator RiskScorer.new(passport).score[:score], :<=, 10.0
  end

  def passed
    { "status" => "passed", "failed" => 0 }
  end

  def passport_in(project, files)
    ws = make_workstream(project: project, branch_name: "feature/rules-#{SecureRandom.hex(4)}")
    make_passport(workstream: ws, files_touched: files, test_summary: passed)
  end

  test "patterns match where a word starts, not anywhere in the path" do
    assert RiskScorer.matches?("app/controllers/sessions_controller.rb", "session")
    assert RiskScorer.matches?("Source/Gurkha/PlayerSessionSubsystem.cpp", "session")
    assert RiskScorer.matches?("db/migrate/20260101_add_users.rb", "migrate")
    assert_not RiskScorer.matches?("docs/decisions/0001-engine.md", "cd")
    assert_not RiskScorer.matches?("app/models/abcd.rb", "cd")
  end

  test "docs/decisions is not flagged as CI" do
    passport = make_passport(files_touched: [file("docs/decisions/0001-engine.md")], test_summary: passed)
    assert_equal "Low", RiskScorer.new(passport).score[:level]
  end

  test "a project rule raises risk for matching paths" do
    project = make_project(risk_rules: { "Config/" => "high" })
    result = RiskScorer.new(passport_in(project, [file("Config/DefaultEngine.ini")])).score
    assert_equal "High", result[:level]
    assert(result[:signals].any? { |s| s[:reason] == "Matches project risk rule: Config/" })
  end

  test "a low project rule silences built-in patterns for that path" do
    project = make_project(risk_rules: { "Source/Gurkha/Session" => "low" })
    passport = passport_in(project, [file("Source/Gurkha/Session/SaveGame.cpp"), file("Source/Gurkha/Session/SaveGameTest.cpp")])
    assert_equal "Low", RiskScorer.new(passport).score[:level]
  end

  test "rules with unknown levels are ignored" do
    project = make_project(risk_rules: { "README" => "warning" })
    assert_equal "Low", RiskScorer.new(passport_in(project, [file("README.md")])).score[:level]
  end
end
