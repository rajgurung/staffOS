class CreateCouncilReviews < ActiveRecord::Migration[8.1]
  def change
    create_table :council_reviews do |t|
      t.references :run_passport, null: false, foreign_key: true
      t.string :persona
      t.string :status
      t.jsonb :findings
      t.text :recommendation
      t.text :risk_assessment
      t.float :score
      t.datetime :completed_at

      t.timestamps
    end
  end
end
