class Setting < ApplicationRecord
  belongs_to :user

  validates :settings, presence: true
end
