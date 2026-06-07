class Workstream < ApplicationRecord
  belongs_to :project

  has_many :agent_sessions, dependent: :nullify
  has_many :run_events, dependent: :nullify
  has_many :run_passports, dependent: :nullify
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

  def current_passport
    run_passports.order(created_at: :desc).first
  end

  def total_sessions
    agent_sessions.count
  end

  def total_events
    run_events.count
  end

  def all_files_touched
    files = {}
    run_passports.each do |passport|
      (passport.files_touched || []).each do |f|
        path = f["path"]
        next unless path
        files[path] ||= { "path" => path, "additions" => 0, "deletions" => 0 }
        files[path]["additions"] += f["additions"].to_i
        files[path]["deletions"] += f["deletions"].to_i
      end
    end
    files.values
  end

  def risk_trend
    run_passports.order(:created_at).pluck(:risk_level)
  end

  def readiness_trend
    run_passports.order(:created_at).pluck(:readiness_score)
  end

  def promote_to_project!
    documents.update_all(workstream_id: nil)
    decision_logs.update_all(workstream_id: nil)
    memory_items.update_all(workstream_id: nil)
    update!(status: "merged", merged_at: Time.current)
  end

  def self.find_or_create_for_branch(project:, branch_name:)
    find_or_create_by!(project: project, branch_name: branch_name) do |ws|
      ws.status = "active"
      ws.title = branch_name.gsub(/[-_\/]/, " ").gsub(/\b\w/, &:upcase)
    end
  end
end
