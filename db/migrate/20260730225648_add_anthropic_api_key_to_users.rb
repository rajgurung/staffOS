class AddAnthropicApiKeyToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :anthropic_api_key, :text
  end
end
