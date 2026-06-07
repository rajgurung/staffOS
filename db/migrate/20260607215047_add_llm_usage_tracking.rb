class AddLlmUsageTracking < ActiveRecord::Migration[8.1]
  def change
    # Per-review token + cost tracking (council mode)
    add_column :council_reviews, :input_tokens, :integer, default: 0, null: false
    add_column :council_reviews, :output_tokens, :integer, default: 0, null: false
    add_column :council_reviews, :cost_cents, :integer, default: 0, null: false
    add_column :council_reviews, :model, :string
    add_column :council_reviews, :source, :string, default: "heuristic", null: false

    # Passport-level rollup of LLM spend across summaries and council reviews
    add_column :run_passports, :input_tokens, :integer, default: 0, null: false
    add_column :run_passports, :output_tokens, :integer, default: 0, null: false
    add_column :run_passports, :cost_cents, :integer, default: 0, null: false
    add_column :run_passports, :summary_source, :string, default: "heuristic", null: false
  end
end
