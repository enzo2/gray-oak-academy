class Applet < ApplicationRecord
  belongs_to :user
  belongs_to :resource, optional: true

  validates :title, presence: true# , unless: :marked_for_destruction?
  validates :code, presence: true# , unless: :marked_for_destruction?
end
