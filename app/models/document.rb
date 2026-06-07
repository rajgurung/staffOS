class Document < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  belongs_to :run_passport, optional: true
  has_many :memory_items, dependent: :nullify

  TYPES = %w[adr decision_log pr_summary risk_item weekly_reflection].freeze

  validates :document_type, inclusion: { in: TYPES }
  validates :title, presence: true

  scope :adrs, -> { where(document_type: "adr") }
  scope :decision_logs, -> { where(document_type: "decision_log") }
  scope :pr_summaries, -> { where(document_type: "pr_summary") }
  scope :risk_items, -> { where(document_type: "risk_item") }

  def type_label
    document_type.titleize
  end

  def type_color
    case document_type
    when "adr" then "purple"
    when "decision_log" then "info"
    when "pr_summary" then "success"
    when "risk_item" then "danger"
    when "weekly_reflection" then "warning"
    else "info"
    end
  end
end
