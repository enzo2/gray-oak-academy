class Setting < ApplicationRecord
  belongs_to :user

  validates :settings, presence: true
  validates :first_name, presence: true
  validates :last_name, presence: true

  def full_name
    "#{first_name} #{last_name}"
  end
end
