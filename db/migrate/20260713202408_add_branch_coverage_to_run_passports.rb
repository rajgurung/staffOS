class AddBranchCoverageToRunPassports < ActiveRecord::Migration[8.1]
  def change
    add_column :run_passports, :branch_coverage, :jsonb
  end
end
