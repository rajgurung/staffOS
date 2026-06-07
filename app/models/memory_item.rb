class MemoryItem < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  belongs_to :document, optional: true

  TYPES = %w[decision pattern convention context constraint].freeze

  validates :memory_type, inclusion: { in: TYPES }
  validates :content, presence: true

  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :by_type, ->(type) { where(memory_type: type) }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def type_color
    case memory_type
    when "decision" then "purple"
    when "pattern" then "info"
    when "convention" then "success"
    when "context" then "warning"
    when "constraint" then "danger"
    else "info"
    end
  end
end
