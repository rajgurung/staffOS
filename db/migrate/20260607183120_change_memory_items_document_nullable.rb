class ChangeMemoryItemsDocumentNullable < ActiveRecord::Migration[8.1]
  def change
    change_column_null :memory_items, :document_id, true
  end
end
