class AgentRun < ApplicationRecord
  validates :run_id, presence: true, uniqueness: true
end
