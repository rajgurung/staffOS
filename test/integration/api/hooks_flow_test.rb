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

  test "the same external session id under different tokens stays isolated per project" do
    other_project = make_project(name: "Other", repo_name: "org/other")
    other_token = other_project.api_tokens.create!(name: "cli")

    post "/api/v1/hooks/session_start",
      params: { session_id: "shared-id", branch_name: "main" }, headers: @headers
    assert_response :success

    post "/api/v1/hooks/post_tool",
      params: { session_id: "shared-id", branch_name: "main", tool_name: "Bash",
                tool_input: { command: "ls" } },
      headers: { "Authorization" => "Bearer #{other_token.token}" }
    assert_response :success

    assert_equal 1, @project.agent_sessions.where(external_session_id: "shared-id").count
    assert_equal 1, other_project.agent_sessions.where(external_session_id: "shared-id").count

    event = other_project.agent_sessions.find_by(external_session_id: "shared-id")
      .run_events.find_by(event_type: "command_run")
    assert_equal other_project, event.workstream.project,
      "events must never attach to another project's session or workstream"
    assert_equal 0, @project.agent_sessions.find_by(external_session_id: "shared-id").run_events
      .where(event_type: "command_run").count
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
