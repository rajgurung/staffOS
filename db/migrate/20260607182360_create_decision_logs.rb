class CreateDecisionLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :decision_logs do |t|
      t.references :project, null: false, foreign_key: true
      t.references :run_passport, null: false, foreign_key: true
      t.string :title
      t.text :context
      t.text :decision
      t.text :rationale
      t.text :consequences
      t.string :status

      t.timestamps
    end
  end
end
