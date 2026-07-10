require "test_helper"

# Projects are owned by users; a signed-in user must only ever see or act on
# their own. These guard against cross-user data exposure.
class ProjectScopingTest < ActionDispatch::IntegrationTest
  setup do
    @owner = User.create!(email: "owner@test.dev", password: "password123")
    @other = User.create!(email: "other@test.dev", password: "password123")
    @owner_project = make_project(name: "Owner Project", user: @owner)
    @other_project = make_project(name: "Other Project", user: @other)
  end

  test "projects index lists only the current user's projects" do
    sign_in @owner
    get projects_path
    assert_response :success
    assert_match "Owner Project", response.body
    assert_no_match "Other Project", response.body
  end

  test "cannot view another user's project" do
    sign_in @owner
    get project_path(@other_project)
    assert_response :not_found
  end

  test "cannot switch context to another user's project" do
    sign_in @owner
    post switch_project_path, params: { project_id: @other_project.id }
    assert_response :not_found
  end

  test "new projects are owned by the current user" do
    sign_in @owner
    assert_difference -> { @owner.projects.count }, 1 do
      post projects_path, params: { project: { name: "Fresh", repo_name: "x/y" } }
    end
    assert_equal @owner, Project.find_by(name: "Fresh").user
  end

  test "cannot view another user's workstream" do
    ws = make_workstream(project: @other_project, branch_name: "feature/secret")
    sign_in @owner
    get workstream_path(ws)
    assert_response :not_found
  end

  test "cannot view another user's passport" do
    session = make_session(project: @other_project)
    passport = session.create_run_passport!(
      intent: "secret", summary: "s", risk_level: "Low", readiness_score: 10,
      human_review_required: false, files_touched: [], test_summary: {},
      missing_checks: [], recommended_actions: []
    )
    sign_in @owner
    get run_passport_path(passport)
    assert_response :not_found
  end

  test "cannot generate a token on another user's project" do
    sign_in @owner
    assert_no_difference -> { @other_project.api_tokens.count } do
      post project_api_tokens_path(@other_project), params: { name: "x" }
    end
    assert_response :not_found
  end
end
