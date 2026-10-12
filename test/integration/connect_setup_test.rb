require "test_helper"

# Setup pages must hand out the same command hooks the CLI installs. HTTP hooks
# carry no git branch, so their events can't land in a branch passport.
class ConnectSetupTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "connect@test.dev", password: "password123")
    @project = make_project(name: "Gurkha", user: @user)
    @project.api_tokens.create!(name: "CLI Token")
    sign_in @user
  end

  test "hook config page shows command hooks without the token" do
    get hook_config_project_path(@project)
    assert_response :success
    assert_match "staffos capture session_start", response.body
    assert_match "staffos capture pre_tool", response.body
    assert_match ".claude/settings.local.json", response.body
    assert_no_match(/&quot;http&quot;|localhost:9090/, response.body)
    assert_no_match @project.api_tokens.first.token, response.body
  end

  test "connect page points at the CLI, not the old script" do
    post switch_project_path, params: { project_id: @project.id }
    get connect_path
    assert_response :success
    assert_match "brew install rajgurung/tap/staffos", response.body
    assert_match "staffos init", response.body
    assert_no_match "connect/script", response.body
  end
end
