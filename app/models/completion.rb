# For storing token usage and cost data.
class Completion < ApplicationRecord
  validates :model, presence: true
end
