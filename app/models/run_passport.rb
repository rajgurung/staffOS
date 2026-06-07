class RunPassport < ApplicationRecord
  belongs_to :agent_session
  belongs_to :workstream, optional: true
  has_one :project, through: :agent_session
  has_many :documents, dependent: :nullify
  has_many :decision_logs, dependent: :nullify
  has_many :council_reviews, dependent: :destroy
  has_many :passport_versions, dependent: :destroy

  REVIEW_MODES = %w[passive smart_summary full_council].freeze

  def create_version!(trigger:)
    next_version = (current_version || 0) + 1
    prev = passport_versions.order(version_number: :desc).first

    changes_desc = if prev
      parts = []
      parts << "readiness #{prev.readiness_score}% → #{readiness_score}%" if prev.readiness_score != readiness_score
      parts << "risk #{prev.risk_level} → #{risk_level}" if prev.risk_level != risk_level
      prev_checks = (prev.missing_checks || []).count
      curr_checks = (missing_checks || []).count
      parts << "#{prev_checks - curr_checks} checks resolved" if prev_checks > curr_checks
      parts.join(". ").presence || "No significant changes."
    end

    version = passport_versions.create!(
      version_number: next_version,
      readiness_score: readiness_score,
      risk_level: risk_level,
      summary: summary,
      files_touched: files_touched,
      test_summary: test_summary,
      missing_checks: missing_checks,
      risk_signals: {},
      trigger: trigger,
      changes_from_previous: changes_desc
    )

    update!(current_version: next_version, last_assessed_at: Time.current)
    version
  end

  def latest_version
    passport_versions.order(version_number: :desc).first
  end

  def review_mode_label
    case review_mode
    when "passive" then "Passive"
    when "smart_summary" then "Smart Summary"
    when "full_council" then "Full Council"
    else "Passive"
    end
  end

  def review_mode_description
    case review_mode
    when "passive" then "Timeline and events only. No LLM analysis."
    when "smart_summary" then "AI-generated summary and risk extraction."
    when "full_council" then "All 6 AI personas review the change."
    else "Timeline and events only."
    end
  end

  def council_completed?
    council_reviews.completed.count == CouncilReview::PERSONAS.count
  end

  def council_progress
    return 0 if council_reviews.empty?
    (council_reviews.completed.count.to_f / CouncilReview::PERSONAS.count * 100).round
  end

  def council_score
    completed = council_reviews.completed
    return nil if completed.empty?
    (completed.average(:score) || 0).round(1)
  end

  def risk_color
    case risk_level&.downcase
    when "low" then "success"
    when "medium" then "warning"
    when "high" then "danger"
    else "info"
    end
  end

  def test_status
    return "Not Run" unless test_summary.present?
    test_summary["status"]&.capitalize || "Unknown"
  end

  def files_count
    files_touched&.length || 0
  end

  def total_additions
    (files_touched || []).sum { |f| f["additions"].to_i }
  end

  def total_deletions
    (files_touched || []).sum { |f| f["deletions"].to_i }
  end

  def duration_minutes
    return nil unless agent_session.started_at && agent_session.completed_at
    ((agent_session.completed_at - agent_session.started_at) / 60).round(1)
  end
end
