class PassportVersion < ApplicationRecord
  belongs_to :run_passport

  TRIGGERS = %w[session_completed council_completed manual_assessment reassessment].freeze

  validates :version_number, presence: true
  validates :trigger, inclusion: { in: TRIGGERS }

  scope :ordered, -> { order(version_number: :asc) }
  scope :latest_first, -> { order(version_number: :desc) }

  def risk_color
    case risk_level&.downcase
    when "low" then "success"
    when "medium" then "warning"
    when "high" then "danger"
    else "info"
    end
  end

  def previous
    run_passport.passport_versions.where("version_number < ?", version_number).order(version_number: :desc).first
  end

  def readiness_delta
    prev = previous
    return nil unless prev
    readiness_score.to_i - prev.readiness_score.to_i
  end
end
