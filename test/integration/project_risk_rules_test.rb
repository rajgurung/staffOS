require "test_helper"

class ProjectRiskRulesTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "rules@test.dev", password: "password123")
    @project = make_project(name: "Gurkha", user: @user, risk_rules: { "Config/" => "high" })
    sign_in @user
  end

  def update_rules(rules)
    patch project_path(@project), params: { project: { name: "Gurkha", risk_rules_submitted: "1", risk_rules: rules }.compact }
  end

  test "removing every rule saves an empty set" do
    update_rules(nil)
    assert_equal({}, @project.reload.risk_rules)
  end

  test "saving unchanged rules doesn't rescore" do
    ws = make_workstream(project: @project, branch_name: "feature/engine")
    passport = make_passport(workstream: ws, risk_level: "Pending")
    update_rules({ "Config/" => "high" })
    assert_equal "Pending", passport.reload.risk_level
  end

  test "blank patterns and unknown levels are dropped" do
    update_rules({ "Config/" => "high", " " => "high", "README" => "warning" })
    assert_equal({ "Config/" => "high" }, @project.reload.risk_rules)
  end

  test "changing rules rescores existing passports" do
    ws = make_workstream(project: @project, branch_name: "feature/engine")
    make_session(project: @project, workstream: ws)
    passport = make_passport(workstream: ws, risk_level: "Pending")
    update_rules({ "README" => "medium" })
    assert_not_equal "Pending", passport.reload.risk_level
  end
end
