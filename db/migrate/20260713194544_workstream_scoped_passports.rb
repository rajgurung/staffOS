class WorkstreamScopedPassports < ActiveRecord::Migration[8.1]
  # Move Run Passports from per-session to per-workstream (SPEC.md §14: one
  # living passport per workstream). Folds existing per-session passports:
  # the newest passport on each workstream survives, older siblings donate
  # their versions and children to it, then the schema enforces uniqueness.

  class MigPassport < ActiveRecord::Base
    self.table_name = "run_passports"
  end

  class MigVersion < ActiveRecord::Base
    self.table_name = "passport_versions"
  end

  def up
    add_reference :passport_versions, :agent_session, null: true, foreign_key: true

    # Versions were created per-session; stamp them with their passport's session.
    execute <<~SQL
      UPDATE passport_versions pv
      SET agent_session_id = rp.agent_session_id
      FROM run_passports rp
      WHERE pv.run_passport_id = rp.id
    SQL

    # Passports on workstream-less sessions (branch unknown) have no home in the
    # new model. Detach their children and drop them.
    orphaned = MigPassport.where(workstream_id: nil).pluck(:id)
    if orphaned.any?
      execute "UPDATE documents SET run_passport_id = NULL WHERE run_passport_id IN (#{orphaned.join(',')})"
      execute "UPDATE decision_logs SET run_passport_id = NULL WHERE run_passport_id IN (#{orphaned.join(',')})"
      execute "DELETE FROM council_reviews WHERE run_passport_id IN (#{orphaned.join(',')})"
      execute "DELETE FROM passport_versions WHERE run_passport_id IN (#{orphaned.join(',')})"
      MigPassport.where(id: orphaned).delete_all
    end

    # Fold: newest passport per workstream survives; older siblings re-point
    # their versions and children to it, then are deleted. Version numbers are
    # rebuilt chronologically so the survivor tells the whole branch's story.
    MigPassport.group(:workstream_id).having("COUNT(*) > 1").count.each_key do |ws_id|
      siblings = MigPassport.where(workstream_id: ws_id).order(:created_at).to_a
      survivor = siblings.pop

      siblings.each do |old|
        MigVersion.where(run_passport_id: old.id).update_all(run_passport_id: survivor.id)
        execute "UPDATE documents SET run_passport_id = #{survivor.id} WHERE run_passport_id = #{old.id}"
        execute "UPDATE decision_logs SET run_passport_id = #{survivor.id} WHERE run_passport_id = #{old.id}"
        execute "UPDATE council_reviews SET run_passport_id = #{survivor.id} WHERE run_passport_id = #{old.id}"
        old.delete
      end

      MigVersion.where(run_passport_id: survivor.id).order(:created_at).each_with_index do |version, i|
        version.update_columns(version_number: i + 1)
      end
      survivor.update_columns(current_version: MigVersion.where(run_passport_id: survivor.id).count)
    end

    remove_reference :run_passports, :agent_session
    change_column_null :run_passports, :workstream_id, false
    remove_index :run_passports, :workstream_id
    add_index :run_passports, :workstream_id, unique: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
