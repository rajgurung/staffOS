# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_07_13_194544) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "agent_sessions", force: :cascade do |t|
    t.string "agent_name"
    t.string "branch_name"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.string "external_session_id"
    t.jsonb "metadata"
    t.bigint "project_id", null: false
    t.string "provider"
    t.datetime "started_at"
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["project_id", "external_session_id"], name: "index_agent_sessions_on_project_and_external_id", unique: true
    t.index ["project_id"], name: "index_agent_sessions_on_project_id"
    t.index ["workstream_id"], name: "index_agent_sessions_on_workstream_id"
  end

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_used_at"
    t.string "name"
    t.bigint "project_id", null: false
    t.string "token"
    t.datetime "updated_at", null: false
    t.index ["project_id"], name: "index_api_tokens_on_project_id"
  end

  create_table "council_reviews", force: :cascade do |t|
    t.datetime "completed_at"
    t.integer "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.jsonb "findings"
    t.integer "input_tokens", default: 0, null: false
    t.string "model"
    t.integer "output_tokens", default: 0, null: false
    t.string "persona"
    t.text "recommendation"
    t.text "risk_assessment"
    t.bigint "run_passport_id", null: false
    t.float "score"
    t.string "source", default: "heuristic", null: false
    t.string "status"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["run_passport_id"], name: "index_council_reviews_on_run_passport_id"
    t.index ["workstream_id"], name: "index_council_reviews_on_workstream_id"
  end

  create_table "decision_logs", force: :cascade do |t|
    t.text "consequences"
    t.text "context"
    t.datetime "created_at", null: false
    t.text "decision"
    t.bigint "project_id", null: false
    t.text "rationale"
    t.bigint "run_passport_id", null: false
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["project_id"], name: "index_decision_logs_on_project_id"
    t.index ["run_passport_id"], name: "index_decision_logs_on_run_passport_id"
    t.index ["workstream_id"], name: "index_decision_logs_on_workstream_id"
  end

  create_table "documents", force: :cascade do |t|
    t.text "content_markdown"
    t.datetime "created_at", null: false
    t.string "document_type"
    t.bigint "project_id", null: false
    t.bigint "run_passport_id", null: false
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["project_id"], name: "index_documents_on_project_id"
    t.index ["run_passport_id"], name: "index_documents_on_run_passport_id"
    t.index ["workstream_id"], name: "index_documents_on_workstream_id"
  end

  create_table "memory_items", force: :cascade do |t|
    t.float "confidence"
    t.text "content"
    t.datetime "created_at", null: false
    t.bigint "document_id"
    t.datetime "expires_at"
    t.string "memory_type"
    t.bigint "project_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["document_id"], name: "index_memory_items_on_document_id"
    t.index ["project_id"], name: "index_memory_items_on_project_id"
    t.index ["workstream_id"], name: "index_memory_items_on_workstream_id"
  end

  create_table "passport_versions", force: :cascade do |t|
    t.bigint "agent_session_id"
    t.text "changes_from_previous"
    t.datetime "created_at", null: false
    t.jsonb "files_touched"
    t.jsonb "missing_checks"
    t.integer "readiness_score"
    t.string "risk_level"
    t.jsonb "risk_signals"
    t.bigint "run_passport_id", null: false
    t.text "summary"
    t.jsonb "test_summary"
    t.string "trigger"
    t.datetime "updated_at", null: false
    t.integer "version_number"
    t.index ["agent_session_id"], name: "index_passport_versions_on_agent_session_id"
    t.index ["run_passport_id"], name: "index_passport_versions_on_run_passport_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.jsonb "documentation_preferences"
    t.string "name"
    t.string "repo_name"
    t.jsonb "risk_rules"
    t.text "tech_stack"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.index ["user_id"], name: "index_projects_on_user_id"
  end

  create_table "run_events", force: :cascade do |t|
    t.bigint "agent_session_id", null: false
    t.datetime "created_at", null: false
    t.string "event_type"
    t.datetime "occurred_at"
    t.jsonb "payload"
    t.string "source"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id"
    t.index ["agent_session_id"], name: "index_run_events_on_agent_session_id"
    t.index ["workstream_id"], name: "index_run_events_on_workstream_id"
  end

  create_table "run_passports", force: :cascade do |t|
    t.integer "cost_cents", default: 0, null: false
    t.datetime "created_at", null: false
    t.integer "current_version", default: 0
    t.jsonb "files_touched"
    t.boolean "human_review_required"
    t.integer "input_tokens", default: 0, null: false
    t.text "intent"
    t.datetime "last_assessed_at"
    t.jsonb "missing_checks"
    t.integer "output_tokens", default: 0, null: false
    t.integer "readiness_score"
    t.jsonb "recommended_actions"
    t.string "review_mode"
    t.string "risk_level"
    t.text "summary"
    t.string "summary_source", default: "heuristic", null: false
    t.jsonb "test_summary"
    t.datetime "updated_at", null: false
    t.bigint "workstream_id", null: false
    t.index ["workstream_id"], name: "index_run_passports_on_workstream_id", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "name"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "workstreams", force: :cascade do |t|
    t.string "branch_name"
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "merged_at"
    t.bigint "project_id", null: false
    t.string "status"
    t.string "title"
    t.datetime "updated_at", null: false
    t.index ["project_id", "branch_name"], name: "index_workstreams_on_project_id_and_branch_name", unique: true
    t.index ["project_id"], name: "index_workstreams_on_project_id"
  end

  add_foreign_key "agent_sessions", "projects"
  add_foreign_key "agent_sessions", "workstreams"
  add_foreign_key "api_tokens", "projects"
  add_foreign_key "council_reviews", "run_passports"
  add_foreign_key "council_reviews", "workstreams"
  add_foreign_key "decision_logs", "projects"
  add_foreign_key "decision_logs", "run_passports"
  add_foreign_key "decision_logs", "workstreams"
  add_foreign_key "documents", "projects"
  add_foreign_key "documents", "run_passports"
  add_foreign_key "documents", "workstreams"
  add_foreign_key "memory_items", "documents"
  add_foreign_key "memory_items", "projects"
  add_foreign_key "memory_items", "workstreams"
  add_foreign_key "passport_versions", "agent_sessions"
  add_foreign_key "passport_versions", "run_passports"
  add_foreign_key "projects", "users"
  add_foreign_key "run_events", "agent_sessions"
  add_foreign_key "run_events", "workstreams"
  add_foreign_key "run_passports", "workstreams"
  add_foreign_key "workstreams", "projects"
end
