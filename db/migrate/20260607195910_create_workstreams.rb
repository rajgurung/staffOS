class CreateWorkstreams < ActiveRecord::Migration[8.1]
  def change
    create_table :workstreams do |t|
      t.references :project, null: false, foreign_key: true
      t.string :branch_name
      t.string :title
      t.string :status
      t.text :description
      t.datetime :merged_at

      t.timestamps
    end
  end
end
