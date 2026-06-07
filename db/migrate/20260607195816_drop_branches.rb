class DropBranches < ActiveRecord::Migration[8.1]
  def up
    drop_table :branches
  end

  def down
    create_table :branches do |t|
      t.references :project, null: false, foreign_key: true
      t.string :name
      t.string :status
      t.text :description
      t.datetime :merged_at
      t.timestamps
    end
  end
end
