class DecisionLog < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  belongs_to :run_passport, optional: true

  validates :title, presence: true
  validates :decision, presence: true

  scope :active, -> { where(status: "active") }
  scope :superseded, -> { where(status: "superseded") }

  STATUSES = %w[draft active superseded deprecated].freeze

  def status_color
    case status
    when "active" then "success"
    when "draft" then "warning"
    when "superseded" then "info"
    when "deprecated" then "danger"
    else "info"
    end
  end
end
