class CreatePassportVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :passport_versions do |t|
      t.references :run_passport, null: false, foreign_key: true
      t.integer :version_number
      t.integer :readiness_score
      t.string :risk_level
      t.text :summary
      t.jsonb :files_touched
      t.jsonb :test_summary
      t.jsonb :missing_checks
      t.jsonb :risk_signals
      t.string :trigger
      t.text :changes_from_previous

      t.timestamps
    end
  end
end
