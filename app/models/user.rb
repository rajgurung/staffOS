class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  #
  # :registerable is intentionally omitted — StaffOS is single-user, and there
  # is no per-user data scoping, so any account sees all data. Public self-
  # signup is disabled; accounts are created via console/seeds. Profile edits
  # go through SettingsController, password resets through :recoverable.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable
end
