class AgentSession < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  has_many :run_events, dependent: :destroy
  has_one :run_passport, dependent: :destroy
end
