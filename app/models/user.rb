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

  # Each account brings its own Anthropic key; council/summary calls for a
  # project bill the project owner's key, never a shared server key.
  encrypts :anthropic_api_key
  validate :anthropic_api_key_looks_valid

  def anthropic_key_hint
    return nil if anthropic_api_key.blank?
    "sk-ant-…#{anthropic_api_key.last(4)}"
  end

  private

  def anthropic_api_key_looks_valid
    return if anthropic_api_key.blank? || anthropic_api_key.start_with?("sk-ant-")
    errors.add(:anthropic_api_key, "should start with sk-ant-")
  end
end
