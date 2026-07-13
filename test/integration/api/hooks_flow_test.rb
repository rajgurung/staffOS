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

  test "post_tool prefers client-computed privacy metadata over deriving from source" do
    sid = "session-sanitized"
    post "/api/v1/hooks/session_start",
      params: { session_id: sid, branch_name: "feature/priv" }, headers: @headers

    # Privacy-enforcing CLI: no old_string/new_string/content, counts precomputed.
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/priv", tool_name: "Edit",
                tool_input: { file_path: "app/models/user.rb", additions: 7, deletions: 2 } },
      headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/priv", tool_name: "Read",
                tool_input: { file_path: "app/models/user.rb", lines: 42 } },
      headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/priv", tool_name: "Bash",
                tool_input: { command: "bin/rails test", exit_code: 1 } },
      headers: @headers
    assert_response :success

    session = @project.agent_sessions.find_by!(external_session_id: sid)
    edit = session.run_events.find_by!(event_type: "file_edited")
    assert_equal 7, edit.payload["additions"]
    assert_equal 2, edit.payload["deletions"]
    assert_nil edit.payload.dig("tool_input", "old_string")

    read = session.run_events.find_by!(event_type: "file_read")
    assert_equal 42, read.payload["lines"]

    bash = session.run_events.find_by!(event_type: "command_run")
    assert_equal 1, bash.payload["exit_code"]
  end

  test "post_tool still derives counts from source for full-capture clients" do
    sid = "session-fullcap"
    post "/api/v1/hooks/session_start",
      params: { session_id: sid, branch_name: "feature/full" }, headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/full", tool_name: "Write",
                tool_input: { file_path: "lib/thing.rb", content: "a\nb\nc" } },
      headers: @headers
    assert_response :success

    event = @project.agent_sessions.find_by!(external_session_id: sid)
      .run_events.find_by!(event_type: "file_edited")
    assert_equal 3, event.payload["additions"]
    assert_equal 0, event.payload["deletions"]
  end

  test "a session that hops branches versions every passport it touched on stop" do
    sid = "session-hopper"
    post "/api/v1/hooks/session_start",
      params: { session_id: sid, branch_name: "feature/a" }, headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/a", tool_name: "Edit",
                tool_input: { file_path: "a.rb", additions: 3, deletions: 1 } },
      headers: @headers
    # user switches branches mid-session; events route to the new workstream
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/b", tool_name: "Edit",
                tool_input: { file_path: "b.rb", additions: 5, deletions: 0 } },
      headers: @headers
    post "/api/v1/hooks/stop",
      params: { session_id: sid, branch_name: "feature/b" }, headers: @headers
    assert_response :success

    session = @project.agent_sessions.find_by!(external_session_id: sid)
    %w[feature/a feature/b].each do |branch|
      ws = @project.workstreams.find_by!(branch_name: branch)
      passport = ws.run_passport
      assert_not_nil passport, "#{branch} must get a passport even though the session stopped elsewhere"
      version = passport.passport_versions.find_by(agent_session: session)
      assert_not_nil version, "#{branch}'s version must be stamped with the hopping session"
    end
    assert_equal ["a.rb"], @project.workstreams.find_by!(branch_name: "feature/a")
      .run_passport.files_touched.map { |f| f["path"] }
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

  test "stop ingests the CLI's branch snapshot and the passport scores coverage" do
    sid = "session-coverage"
    post "/api/v1/hooks/session_start",
      params: { session_id: sid, branch_name: "feature/cov" }, headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: sid, branch_name: "feature/cov", tool_name: "Edit",
                tool_input: { file_path: "/repo/app/models/user.rb", old_string: "a", new_string: "b" } },
      headers: @headers
    post "/api/v1/hooks/stop",
      params: { session_id: sid, branch_name: "feature/cov",
                branch_snapshot: {
                  base_branch: "origin/main", merge_base: "abc123",
                  files: [
                    { path: "app/models/user.rb", additions: 1, deletions: 1 },
                    { path: "lib/manual_tweak.rb", additions: 30, deletions: 0 }
                  ]
                } },
      headers: @headers
    assert_response :success

    ws = @project.workstreams.find_by!(branch_name: "feature/cov")
    assert_equal 1, ws.run_events.where(event_type: "branch_snapshot").count

    coverage = ws.run_passport.branch_coverage
    assert_equal 2, coverage["branch_files"]
    assert_equal 1, coverage["observed"]
    assert_equal ["lib/manual_tweak.rb"], coverage["unobserved_paths"]
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

    passport = session.workstream.run_passport
    assert_not_nil passport, "expected a passport to be generated on stop"
    assert_equal "Add login", passport.intent
    assert_operator passport.passport_versions.count, :>=, 1
    assert_equal "feature/login", passport.workstream.branch_name
  end

  test "two sessions on one branch accumulate into a single passport with per-session versions" do
    branch = "feature/cumulative"

    # Session 1: edits one file, runs no tests.
    post "/api/v1/hooks/session_start",
      params: { session_id: "cum-1", branch_name: branch }, headers: @headers
    post "/api/v1/hooks/prompt",
      params: { session_id: "cum-1", branch_name: branch, prompt: "Build the alpha widget" }, headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: "cum-1", branch_name: branch, tool_name: "Edit",
                tool_input: { file_path: "app/models/alpha.rb", old_string: "a", new_string: "a\nb" } },
      headers: @headers
    post "/api/v1/hooks/stop",
      params: { session_id: "cum-1", branch_name: branch }, headers: @headers
    assert_response :success

    # Session 2: edits another file and runs a passing test command.
    post "/api/v1/hooks/session_start",
      params: { session_id: "cum-2", branch_name: branch }, headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: "cum-2", branch_name: branch, tool_name: "Edit",
                tool_input: { file_path: "app/services/beta.rb", old_string: "x", new_string: "x\ny" } },
      headers: @headers
    post "/api/v1/hooks/post_tool",
      params: { session_id: "cum-2", branch_name: branch, tool_name: "Bash",
                tool_input: { command: "bin/rails test" } },
      headers: @headers
    post "/api/v1/hooks/stop",
      params: { session_id: "cum-2", branch_name: branch }, headers: @headers
    assert_response :success

    ws = Workstream.find_by(project: @project, branch_name: branch)
    assert_equal 1, RunPassport.where(workstream: ws).count
    passport = ws.run_passport

    paths = passport.files_touched.map { |f| f["path"] }
    assert_includes paths, "app/models/alpha.rb"
    assert_includes paths, "app/services/beta.rb"

    v1 = passport.passport_versions.find_by(version_number: 1)
    v2 = passport.passport_versions.find_by(version_number: 2)
    assert_not_nil v1
    assert_not_nil v2
    assert_operator v2.readiness_score, :>, v1.readiness_score,
      "adding test evidence in session 2 should raise readiness"
    assert_match(/readiness/, v2.changes_from_previous)
    assert_equal "cum-1", v1.agent_session.external_session_id
    assert_equal "cum-2", v2.agent_session.external_session_id
  end

  test "sessions on an unknown branch capture events but never a passport" do
    assert_no_difference -> { RunPassport.count } do
      post "/api/v1/hooks/session_start",
        params: { session_id: "nb-1", branch_name: "unknown" }, headers: @headers
      post "/api/v1/hooks/post_tool",
        params: { session_id: "nb-1", branch_name: "unknown", tool_name: "Edit",
                  tool_input: { file_path: "app/models/x.rb", old_string: "a", new_string: "b" } },
        headers: @headers
      post "/api/v1/hooks/stop",
        params: { session_id: "nb-1", branch_name: "unknown" }, headers: @headers
      assert_response :success
    end

    session = @project.agent_sessions.find_by(external_session_id: "nb-1")
    assert_nil session.workstream
    assert_equal "completed", session.status
    assert_operator session.run_events.count, :>=, 2
  end
end
