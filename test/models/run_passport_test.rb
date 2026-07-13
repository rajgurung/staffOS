require "test_helper"

class RunPassportTest < ActiveSupport::TestCase
  test "create_version! snapshots state and increments the version number" do
    passport = make_passport(readiness_score: 42, risk_level: "High")

    v1 = passport.create_version!(trigger: "session_completed")
    assert_equal 1, v1.version_number
    assert_equal 1, passport.reload.current_version

    passport.update!(readiness_score: 68, risk_level: "Medium")
    v2 = passport.create_version!(trigger: "council_completed")

    assert_equal 2, v2.version_number
    assert_equal "council_completed", v2.trigger
    assert_match(/readiness 42% → 68%/, v2.changes_from_previous)
    assert_match(/risk High → Medium/, v2.changes_from_previous)
  end

  test "council_completed? is true only once every persona has reviewed" do
    passport = make_passport
    assert_not passport.council_completed?

    without_llm do
      CouncilRunner.new(passport).run!
    end

    assert passport.reload.council_completed?
    assert_equal 100, passport.council_progress
  end

  test "the database enforces one passport per workstream" do
    passport = make_passport
    duplicate = RunPassport.new(
      workstream: passport.workstream,
      intent: "dup", summary: "s", risk_level: "Low",
      readiness_score: 1, human_review_required: false
    )
    assert_raises(ActiveRecord::RecordNotUnique) { duplicate.save(validate: false) }
  end

  test "risk_color maps levels to UI tokens" do
    assert_equal "danger", make_passport(risk_level: "High").risk_color
    assert_equal "warning", make_passport(risk_level: "Medium").risk_color
    assert_equal "success", make_passport(risk_level: "Low").risk_color
  end
end
