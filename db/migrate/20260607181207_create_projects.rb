class CreateProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :projects do |t|
      t.string :name
      t.string :repo_name
      t.text :tech_stack
      t.jsonb :risk_rules
      t.jsonb :documentation_preferences

      t.timestamps
    end
  end
end
