class AgentSession < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  has_many :run_events, dependent: :destroy
  has_many :passport_versions, dependent: :nullify
end
