require "test_helper"

class Api::HooksFlowTest < ActionDispatch::IntegrationTest
  def setup
    @project = make_project(name: "Hooked", repo_name: "org/hooked")
    @token = @project.api_tokens.create!(name: "ci")
    @headers = {
      "Authorization" => "Bearer #{@token.token}",
      "X-StaffOS-Project" => @project.name
    }
  end

  test "unauthenticated requests are rejected in non-development" do
    post "/api/v1/hooks/session_start", params: { session_id: "s1", branch_name: "feature/x" }
    assert_response :unauthorized
  end

  test "ingestion targets the token's project, ignoring a spoofed project header" do
    victim = make_project(name: "Victim", repo_name: "org/victim")

    post "/api/v1/hooks/session_start",
      params: { session_id: "spoof-1", branch_name: "feature/x" },
      headers: { "Authorization" => "Bearer #{@token.token}", "X-StaffOS-Project" => victim.name }
    assert_response :success

    session = AgentSession.find_by(external_session_id: "spoof-1")
    assert_equal @project, session.project, "session must land on the token's project, not the header's"
    assert_equal 0, victim.agent_sessions.count
  end

  test "a full session lifecycle produces a passport with a version" do
    sid = "session-abc"

    post "/api/v1/hooks/session_start",
      params: { session_id: sid, branch_name: "feature/login" }, headers: @headers
    assert_response :success

    post "/api/v1/hooks/prompt",
      params: { session_id: sid, branch_name: "feature/login", prompt: "Add login" }, headers: @headers

    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/login", tool_name: "Edit",
                tool_input: { file_path: "app/models/user.rb", old_string: "a", new_string: "a\nb" } },
      headers: @headers

    post "/api/v1/hooks/stop",
      params: { session_id: sid, branch_name: "feature/login" }, headers: @headers
    assert_response :success

    session = AgentSession.find_by(external_session_id: sid)
    assert_equal "completed", session.status

    passport = session.run_passport
    assert_not_nil passport, "expected a passport to be generated on stop"
    assert_equal "Add login", passport.intent
    assert_operator passport.passport_versions.count, :>=, 1
    assert_equal "feature/login", passport.workstream.branch_name
  end
end
