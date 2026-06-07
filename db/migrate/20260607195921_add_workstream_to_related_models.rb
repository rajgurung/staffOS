class AddWorkstreamToRelatedModels < ActiveRecord::Migration[8.1]
  def change
    add_reference :agent_sessions, :workstream, null: true, foreign_key: true
    add_reference :run_passports, :workstream, null: true, foreign_key: true
    add_reference :run_events, :workstream, null: true, foreign_key: true
    add_reference :documents, :workstream, null: true, foreign_key: true
    add_reference :decision_logs, :workstream, null: true, foreign_key: true
    add_reference :memory_items, :workstream, null: true, foreign_key: true
    add_reference :council_reviews, :workstream, null: true, foreign_key: true

    add_column :run_passports, :current_version, :integer, default: 0
    add_column :run_passports, :last_assessed_at, :datetime

    add_index :workstreams, [:project_id, :branch_name], unique: true
  end
end
