require "test_helper"

class DocumentGeneratorTest < ActiveSupport::TestCase
  def setup
    @passport = make_passport(
      files_touched: [
        { "path" => "app/services/retry_handler.rb", "additions" => 40, "deletions" => 5, "category" => "service" }
      ],
      test_summary: { "status" => "passed", "total" => 12, "failed" => 0 },
      intent: "Harden retry handling for inference callbacks",
      summary: "Added bounded retries with idempotency keys. Needs an ADR.",
      risk_level: "Medium",
      readiness_score: 70,
      missing_checks: [{ "check" => "Missing idempotency test", "severity" => "medium" }],
      recommended_actions: [{ "action" => "Add idempotency spec", "priority" => "high" }]
    )
    @generator = DocumentGenerator.new(@passport)
  end

  test "generates an ADR document with rendered context" do
    doc = @generator.generate_adr!
    assert_equal "adr", doc.document_type
    assert_match "Harden retry handling", doc.title
    assert_match "Risk Level", doc.content_markdown
    assert_equal @passport.project, doc.project
  end

  test "generates a PR summary" do
    doc = @generator.generate_pr_summary!
    assert_equal "pr_summary", doc.document_type
    assert_match "## Summary", doc.content_markdown
  end

  test "generates a decision log" do
    log = @generator.generate_decision_log!
    assert log.title.present?
    assert log.decision.present?
    assert_equal @passport, log.run_passport
  end

  test "generates a memory item with confidence derived from readiness" do
    item = @generator.generate_memory_item!
    assert_equal "decision", item.memory_type
    assert_in_delta 0.70, item.confidence, 0.001
  end
end
