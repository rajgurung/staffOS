class AddReviewModeToRunPassports < ActiveRecord::Migration[8.1]
  def change
    add_column :run_passports, :review_mode, :string
  end
end
