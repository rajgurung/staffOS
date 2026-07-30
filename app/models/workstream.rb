class Workstream < ApplicationRecord
  belongs_to :project

  has_many :agent_sessions, dependent: :nullify
  has_many :run_events, dependent: :nullify
  has_one :run_passport, dependent: :destroy
  has_many :documents, dependent: :nullify
  has_many :decision_logs, dependent: :nullify
  has_many :memory_items, dependent: :nullify
  has_many :council_reviews, dependent: :nullify

  STATUSES = %w[active in_review merged archived].freeze

  validates :branch_name, presence: true
  validates :branch_name, uniqueness: { scope: :project_id }
  validates :status, inclusion: { in: STATUSES }

  scope :active, -> { where(status: "active") }
  scope :in_review, -> { where(status: "in_review") }
  scope :merged, -> { where(status: "merged") }
  scope :recent, -> { order(updated_at: :desc) }

  def display_name
    title.presence || branch_name
  end

  def status_color
    case status
    when "active" then "success"
    when "in_review" then "warning"
    when "merged" then "info"
    when "archived" then "danger"
    else "info"
    end
  end

  def total_sessions
    agent_sessions.count
  end

  def total_events
    run_events.count
  end

  def all_files_touched
    run_passport&.files_touched || []
  end

  def risk_trend
    return [] unless run_passport
    run_passport.passport_versions.ordered.pluck(:risk_level)
  end

  def readiness_trend
    return [] unless run_passport
    run_passport.passport_versions.ordered.pluck(:readiness_score)
  end

  def promote_to_project!
    documents.update_all(workstream_id: nil)
    decision_logs.update_all(workstream_id: nil)
    memory_items.update_all(workstream_id: nil)
    update!(status: "merged", merged_at: Time.current)
  end

  # Branch names arrive from clients and have drifted in the wild (whitespace,
  # refs/heads/ prefixes). Every lookup MUST go through this or near-identical
  # names mint duplicate workstreams — and therefore duplicate passports.
  def self.normalize_branch(raw)
    raw.to_s.strip.delete_prefix("refs/heads/")
  end

  def self.find_or_create_for_branch(project:, branch_name:)
    branch_name = normalize_branch(branch_name)
    find_or_create_by!(project: project, branch_name: branch_name) do |ws|
      ws.status = "active"
      ws.title = branch_name.gsub(/[-_\/]/, " ").gsub(/\b\w/, &:upcase)
    end
  end
end
