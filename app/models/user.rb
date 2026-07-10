class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  #
  # :registerable is intentionally omitted — public self-signup is disabled;
  # accounts are created via console/seeds. Data is scoped per-user (projects
  # belong to a user), so accounts don't see each other's data. Profile edits
  # go through SettingsController, password resets through :recoverable.
  devise :database_authenticatable,
         :recoverable, :rememberable, :validatable

  # Deleting a user with projects is blocked — reassign the projects first.
  has_many :projects, dependent: :restrict_with_error
end
