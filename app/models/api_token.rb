class ApiToken < ApplicationRecord
  belongs_to :project

  before_create :generate_token

  validates :name, presence: true

  def masked_token
    "#{token[0..7]}...#{token[-4..]}"
  end

  private

  def generate_token
    self.token = SecureRandom.hex(32)
  end
end
