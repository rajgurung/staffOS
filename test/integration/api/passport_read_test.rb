require "test_helper"

class Api::PassportReadTest < ActionDispatch::IntegrationTest
  setup do
    @project = make_project(name: "Gurkha", repo_name: "rajgurung/gurkha")
    @token = @project.api_tokens.create!(name: "cli")
    @ws = make_workstream(project: @project, branch_name: "feature/stealth")
    make_session(project: @project, workstream: @ws)
    @passport = make_passport(workstream: @ws, readiness_score: 72, risk_level: "Medium",
      missing_checks: [{ "check" => "No test evidence found", "severity" => "high", "source" => "heuristic" }])
  end

  def get_passport(branch, token: @token.token)
    get "/api/v1/passport", params: { branch: branch }, headers: { "Authorization" => "Bearer #{token}" }
  end

  test "returns the branch passport for the token's project" do
    get_passport("feature/stealth")
    assert_response :success
    body = response.parsed_body
    assert_equal "feature/stealth", body["branch"]
    assert_equal 72, body["readiness_score"]
    assert_equal "Medium", body["risk_level"]
    assert_equal 1, body["sessions_count"]
    assert_equal [{ "check" => "No test evidence found", "severity" => "high" }], body["missing_checks"]
    assert_match %r{/run_passports/#{@passport.id}\z}, body["url"]
  end

  test "unknown branch is a 404" do
    get_passport("feature/nope")
    assert_response :not_found
  end

  test "cannot read another project's passport" do
    other = make_project(name: "Other")
    other_token = other.api_tokens.create!(name: "cli")
    get_passport("feature/stealth", token: other_token.token)
    assert_response :not_found
  end

  test "requires a token" do
    get "/api/v1/passport", params: { branch: "feature/stealth" }
    assert_response :unauthorized
  end
end
