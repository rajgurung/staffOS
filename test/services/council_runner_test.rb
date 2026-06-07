require "test_helper"

class CouncilRunnerTest < ActiveSupport::TestCase
  def setup
    @passport = make_passport(
      files_touched: [
        { "path" => "app/controllers/payments_controller.rb", "additions" => 30, "deletions" => 2, "category" => "controller" }
      ],
      test_summary: { "status" => "passed", "failed" => 0 },
      intent: "Add retry logic to payment callbacks"
    )
  end

  test "run! produces one completed review per persona" do
    without_llm do
      CouncilRunner.new(@passport).run!
    end

    assert_equal CouncilReview::PERSONAS.count, @passport.council_reviews.completed.count
    @passport.council_reviews.each do |review|
      assert_equal "completed", review.status
      assert_operator review.score, :>=, 1.0
      assert_operator review.score, :<=, 10.0
    end
  end

  test "reviews fall back to heuristics with zero cost when the LLM is disabled" do
    without_llm do
      CouncilRunner.new(@passport).run!
    end

    @passport.council_reviews.each do |review|
      assert_equal "heuristic", review.source
      assert_equal 0, review.cost_cents
    end
    assert_equal 0, @passport.reload.cost_cents
  end

  test "the security reviewer flags auth/payment surfaces" do
    review = without_llm do
      CouncilRunner.new(@passport).run_persona!("security")
    end

    assert_equal "security", review.persona
    assert review.findings.any? { |f| f["type"] == "payment" || f["severity"] == "critical" },
      "expected the security reviewer to raise a payment/critical finding"
  end
end
