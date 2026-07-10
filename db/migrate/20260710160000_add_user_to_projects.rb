class AddUserToProjects < ActiveRecord::Migration[8.1]
  def up
    add_reference :projects, :user, foreign_key: true, index: true, null: true

    # Backfill existing (ownerless) projects to the first user by id. On prod,
    # delete the demo seed users BEFORE this runs so the owner is the real
    # account, not raj@staffos.dev. Presence is enforced at the model level
    # (belongs_to :user), so the column stays nullable to keep deploys safe if
    # no users exist yet.
    owner = User.order(:id).first
    Project.where(user_id: nil).update_all(user_id: owner.id) if owner
  end

  def down
    remove_reference :projects, :user
  end
end
