class AgentApiEvent < ApplicationRecord
  belongs_to :user
  belongs_to :agent_api_key

  validates :request_method, :path, :requested_at, presence: true

  scope :recent_first, -> { order(requested_at: :desc, created_at: :desc) }
end
