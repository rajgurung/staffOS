class CreateRunPassports < ActiveRecord::Migration[8.1]
  def change
    create_table :run_passports do |t|
      t.references :agent_session, null: false, foreign_key: true
      t.text :intent
      t.text :summary
      t.string :risk_level
      t.integer :readiness_score
      t.boolean :human_review_required
      t.jsonb :test_summary
      t.jsonb :files_touched
      t.jsonb :missing_checks
      t.jsonb :recommended_actions

      t.timestamps
    end
  end
end
