class RunEvent < ApplicationRecord
  belongs_to :agent_session
  belongs_to :workstream, optional: true
end
