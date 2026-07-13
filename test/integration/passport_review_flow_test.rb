require "test_helper"

# Exercises the authenticated UI flows end to end: dashboard, passport views,
# review-mode switches (smart summary + full council), and document generation.
# The LLM is disabled in tests, so these traverse the deterministic fallbacks.
class PassportReviewFlowTest < ActionDispatch::IntegrationTest
  def setup
    sign_in_user
    @passport = make_passport(
      files_touched: [
        { "path" => "app/services/retry_handler.rb", "additions" => 40, "deletions" => 5, "category" => "service" }
      ],
      test_summary: { "status" => "passed", "total" => 12, "failed" => 0 },
      intent: "Harden retry handling",
      summary: "Bounded retries with idempotency."
    )
  end

  test "dashboard renders" do
    get dashboard_path
    assert_response :success
  end

  test "passport index and show render" do
    get run_passports_path
    assert_response :success

    get run_passport_path(@passport)
    assert_response :success
    assert_select "body"
  end

  test "smart summary mode falls back to heuristics without a key" do
    post set_review_mode_run_passport_path(@passport), params: { mode: "smart_summary" }
    assert_redirected_to run_passport_path(@passport)
    assert_equal "smart_summary", @passport.reload.review_mode
    follow_redirect!
    assert_response :success
  end

  test "full council mode runs reviews and snapshots a version" do
    assert_difference -> { @passport.council_reviews.completed.count }, CouncilReview::PERSONAS.count do
      post set_review_mode_run_passport_path(@passport), params: { mode: "full_council" }
    end
    assert @passport.reload.passport_versions.where(trigger: "council_completed").exists?
  end

  test "documents and decision logs can be generated from a passport" do
    assert_difference -> { Document.count }, 1 do
      post generate_document_run_passport_path(@passport), params: { doc_type: "adr" }
    end
    assert_difference -> { DecisionLog.count }, 1 do
      post generate_document_run_passport_path(@passport), params: { doc_type: "decision_log" }
    end
  end

  test "passport exports as markdown and json" do
    get export_run_passport_path(@passport, format: :json)
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal @passport.intent, body["intent"]

    get export_run_passport_path(@passport)
    assert_response :success
    assert_match(/Run Passport/, response.body)
  end
end
