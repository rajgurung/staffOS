require "test_helper"

class WorkstreamTest < ActiveSupport::TestCase
  test "find_or_create_for_branch is idempotent per project + branch" do
    project = make_project
    a = Workstream.find_or_create_for_branch(project: project, branch_name: "rr-553-ai-hardening")
    b = Workstream.find_or_create_for_branch(project: project, branch_name: "rr-553-ai-hardening")

    assert_equal a.id, b.id
    assert_equal "active", a.status
    assert_equal "Rr 553 Ai Hardening", a.title
  end

  test "branch names are unique within a project but not across projects" do
    p1 = make_project(name: "One", repo_name: "org/one")
    p2 = make_project(name: "Two", repo_name: "org/two")

    Workstream.create!(project: p1, branch_name: "main", status: "active")
    assert_raises(ActiveRecord::RecordInvalid) do
      Workstream.create!(project: p1, branch_name: "main", status: "active")
    end
    assert Workstream.create!(project: p2, branch_name: "main", status: "active").persisted?
  end

  test "promote_to_project! merges artifacts to the project level" do
    project = make_project
    ws = make_workstream(project: project, branch_name: "feature/promote-me")
    session = make_session(project: project, workstream: ws)
    passport = session.create_run_passport!(intent: "x", summary: "y", risk_level: "Low",
                                             readiness_score: 80, human_review_required: false)
    doc = Document.create!(project: project, workstream: ws, run_passport: passport,
                           document_type: "adr", title: "ADR")

    ws.promote_to_project!

    assert_equal "merged", ws.reload.status
    assert_not_nil ws.merged_at
    assert_nil doc.reload.workstream_id
  end
end
