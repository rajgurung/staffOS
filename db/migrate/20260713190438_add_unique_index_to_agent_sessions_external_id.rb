class AddUniqueIndexToAgentSessionsExternalId < ActiveRecord::Migration[8.1]
  def change
    add_index :agent_sessions, [ :project_id, :external_session_id ], unique: true,
      name: "index_agent_sessions_on_project_and_external_id"
  end
end
