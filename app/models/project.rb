class Project < ApplicationRecord
  has_many :workstreams, dependent: :destroy
  has_many :agent_sessions, dependent: :destroy
  has_many :run_passports, through: :agent_sessions
  has_many :documents, dependent: :destroy
  has_many :decision_logs, dependent: :destroy
  has_many :memory_items, dependent: :destroy
  has_many :api_tokens, dependent: :destroy

  def tech_stack_list
    tech_stack.to_s.split(",").map(&:strip)
  end
end
