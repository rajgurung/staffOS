class AgentSession < ApplicationRecord
  belongs_to :project
  belongs_to :workstream, optional: true
  has_many :run_events, dependent: :destroy
  has_many :passport_versions, dependent: :nullify

  # A session can hop branches mid-flight; `workstream` is only where it
  # started. The branches it actually fed are derived from its events.
  has_many :touched_workstreams, -> { distinct }, through: :run_events, source: :workstream
end
