class CreateAgentSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :agent_sessions do |t|
      t.references :project, null: false, foreign_key: true
      t.string :external_session_id
      t.string :provider
      t.string :agent_name
      t.string :branch_name
      t.string :status
      t.datetime :started_at
      t.datetime :completed_at
      t.jsonb :metadata

      t.timestamps
    end
  end
end
