class CreateMemoryItems < ActiveRecord::Migration[8.1]
  def change
    create_table :memory_items do |t|
      t.references :project, null: false, foreign_key: true
      t.references :document, null: false, foreign_key: true
      t.string :memory_type
      t.text :content
      t.float :confidence
      t.datetime :expires_at

      t.timestamps
    end
  end
end
