class CreateApiTokens < ActiveRecord::Migration[8.1]
  def change
    create_table :api_tokens do |t|
      t.references :project, null: false, foreign_key: true
      t.string :token
      t.string :name
      t.datetime :last_used_at

      t.timestamps
    end
  end
end
