class CouncilReview < ApplicationRecord
  belongs_to :run_passport
  belongs_to :workstream, optional: true

  PERSONAS = {
    "staff_engineer" => { label: "Staff Engineer", icon: "SE", color: "blue" },
    "sre" => { label: "SRE Reviewer", icon: "SR", color: "cyan" },
    "security" => { label: "Security Reviewer", icon: "SC", color: "purple" },
    "product_manager" => { label: "Product Manager", icon: "PM", color: "teal" },
    "devils_advocate" => { label: "Devil's Advocate", icon: "DA", color: "orange" },
    "writing_coach" => { label: "Writing Coach", icon: "WC", color: "rose" }
  }.freeze

  STATUSES = %w[pending running completed failed].freeze

  validates :persona, inclusion: { in: PERSONAS.keys }
  validates :status, inclusion: { in: STATUSES }

  scope :completed, -> { where(status: "completed") }
  scope :ordered, -> { order(Arel.sql("array_position(ARRAY['staff_engineer','sre','security','product_manager','devils_advocate','writing_coach'], persona)")) }

  def persona_config
    PERSONAS[persona] || {}
  end

  def label
    persona_config[:label] || persona.titleize
  end

  def icon
    persona_config[:icon] || "?"
  end

  def color
    persona_config[:color] || "primary"
  end

  def completed?
    status == "completed"
  end

  def running?
    status == "running"
  end
end
