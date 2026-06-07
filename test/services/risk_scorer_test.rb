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
end
