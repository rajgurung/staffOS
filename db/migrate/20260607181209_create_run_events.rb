class CreateRunEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :run_events do |t|
      t.references :agent_session, null: false, foreign_key: true
      t.string :event_type
      t.datetime :occurred_at
      t.jsonb :payload
      t.string :source

      t.timestamps
    end
  end
end
