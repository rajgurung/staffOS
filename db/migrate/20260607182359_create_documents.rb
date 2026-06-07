class CreateDocuments < ActiveRecord::Migration[8.1]
  def change
    create_table :documents do |t|
      t.references :project, null: false, foreign_key: true
      t.references :run_passport, null: false, foreign_key: true
      t.string :document_type
      t.string :title
      t.text :content_markdown
      t.string :status

      t.timestamps
    end
  end
end
